// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Constant.sol";

library NestedCodeHash {
    function codeHash(address target) public returns (bytes32) {
        bytes memory code = target.code;
        if (code.length == 23 && code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00) {
            uint256 t = 0;
            for (uint256 i = 0; i < 20; i++) {
                t += uint8(code[i + 3]) * (0x100 ** (19 - i));
            }
            return address(uint160(t)).codehash;
        }
        return bytes32(0);
    }
}

contract GLDToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Gold", "GLD") {
        _mint(msg.sender, initialSupply);
    }
}

contract SLVToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Silver", "SLV") {
        _mint(msg.sender, initialSupply);
    }
}

contract U3Wrap1 {
    function getCode() external view returns (bytes memory) {
        return Constant.U3Pool;
    }
}

contract U3Wrap2 {
    function getCode() external view returns (bytes memory) {
        return Constant2.U3Pool;
    }
}

contract TramEVController is Ownable(msg.sender), IUniswapV3SwapCallback {
    ISwapRouter public immutable swapRouterV3;

    using NestedCodeHash for address;

    // Uniswap V3 Factory address (mainnet)
    address public constant UNISWAP_V3_FACTORY = 0x414141418Ad98523631ae4a59F267346ea31f984;
    bytes32 public constant UNISWAP_V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    address private swapTokenIn;
    address private swapTokenOut;
    mapping(address => uint256) cached;
    uint24 private swapFee;
    uint256 private swapAmountIn;
    address U3Code;
    address U3Code2;

    address GOLD;
    address SILVER;

    constructor(address _swapRouterV3, address[] memory tokens, address _code1, address _code2) {
        require(tokens.length >= 6, "need more tokens");
        swapRouterV3 = ISwapRouter(_swapRouterV3);
        U3Code = _code1;
        U3Code2 = _code2;
        GOLD = tokens[0];
        SILVER = tokens[1];
        require(keccak256(abi.encodePacked(U3Wrap1(_code1).getCode(), U3Wrap1(_code2).getCode())) == UNISWAP_V3_POOL_INIT_CODE_HASH, "call admin");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(address(swapRouterV3), type(uint256).max);
        }
    }

    receive() external payable {}

    function deployCheck() internal returns (address addr) {
        bytes memory m = abi.encodePacked(U3Wrap1(U3Code).getCode(), U3Wrap1(U3Code2).getCode());
        assembly {
            addr := create(0, add(m, 0x20), mload(m))
        }
    }

    fallback() external payable onlyOwner {
        bytes memory data = msg.data;
        require(data.length > 0, "No data");

        uint8 mode = uint8(data[data.length - 1]);
        if (mode == 37) {
            _handleV3Swap(data);
        } else {
            revert("Unsupported mode");
        }
    }

    function _handleV3Swap(bytes memory data) internal { // initial settings
        (address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMin) =
            abi.decode(data, (address, address, uint24, uint256, uint256));
        // initial call: gld, slv, 1, 1, 99_999_999 * 1e18
            // amountOutMin: 99_999_999 * 1e18
        
        swapTokenIn = tokenIn; // gld
        swapTokenOut = tokenOut; // slv
        swapFee = fee; // 1
        swapAmountIn = amountIn; // 1

        uint256 b0 = IERC20(tokenIn).balanceOf(address(this)); // gld => 100_000_000
        uint256 b1 = IERC20(tokenOut).balanceOf(address(this)); // slv => 100_000_000

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        (bool success, bytes memory reason) =
            address(swapRouterV3).call(abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params));
        // swapRouterV3.exactInputSingle(params)
        require(success, "huh");
        require(b0 + amountIn >= IERC20(tokenIn).balanceOf(address(this)), "not enough balance");
        // 100_000_000 + 1 >= gld balance of this contract
    }

    function parameters()
        external
        view
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
    {
        return (sFactory, sToken0, sToken1, sFee, sTickSpacing);
    }

    address sFactory;
    address sToken0;
    address sToken1;
    uint24 sFee;
    int24 sTickSpacing;

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        uint256 amountToPay = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        require(amountToPay <= swapAmountIn, "Over-requested");

        bool successPoolAddress;
        bool successCodeHash;
        if (cached[msg.sender] > 0 && cached[msg.sender] < block.number) {
            successPoolAddress = true;
            successCodeHash = true;
        } else {
            address expectedPool = verifyV3Pool(swapTokenIn, swapTokenOut, swapFee);
            if (msg.sender == expectedPool) successPoolAddress = true;
            if (address(msg.sender).codeHash() == UNISWAP_V3_POOL_INIT_CODE_HASH) successCodeHash = true;

            IUniswapV3Pool up = IUniswapV3Pool(msg.sender);
            sFactory = up.factory();
            sToken0 = up.token0();
            sToken1 = up.token1();
            sFee = up.fee();
            sTickSpacing = up.tickSpacing();

            address dc = deployCheck();
            bytes memory check = dc.code;

            uint256 convertedAddress = uint256(uint160(msg.sender));

            assembly {
                mstore(add(check, 11291), convertedAddress)
            }

            if (address(msg.sender).codeHash() == keccak256(check)) successCodeHash = true;
        }

        require(successPoolAddress || successCodeHash, "Security check failed");
        cached[msg.sender] = block.number;

        if (amount0Delta > 0) {
            IERC20(swapTokenIn).transfer(msg.sender, amountToPay);
        } if (amount1Delta > 0) {
            IERC20(swapTokenOut).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function verifyV3Pool(address tokenA, address tokenB, uint24 fee) internal view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        bytes32 salt = keccak256(abi.encode(token0, token1, fee));
        address pool = address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", UNISWAP_V3_FACTORY, salt, UNISWAP_V3_POOL_INIT_CODE_HASH)))
            )
        );

        return pool;
    }

    bool public isSolved;

    function solve() external {
        if (IERC20(SILVER).balanceOf(msg.sender) == 100_000_000 * 1e18) isSolved = true;
    }
}
