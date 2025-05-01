#!/usr/bin/env python3
from web3 import Web3
import os

ABI = [
    {
        "type": "function",
        "name": "isSolved",
        "inputs": [],
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
    }
]

rpc_url = os.environ["RPC_URL"]
user_address = os.environ["USER_ADDRESS"]
contract_address = os.environ["TRAMEV_CONTRACT_ADDRESS"]


def verify():
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    assert w3.is_connected(), "RPC server must be connectable"

    contract = w3.eth.contract(address=contract_address, abi=ABI)
    is_solved = contract.functions.isSolved().call()
    return is_solved


if __name__ == "__main__":
    if verify():
        exit(0)
    exit(1)
