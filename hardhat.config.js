require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.25",
        settings: {
          optimizer: {
            enabled: true,
            runs: 50,
          },
          viaIR: true,
          outputSelection: {
            "*": {
              "": ["ast"],
              "*": [
                "abi",
                "metadata",
                "devdoc",
                "userdoc",
                "storageLayout",
                "evm.legacyAssembly",
                "evm.bytecode",
                "evm.deployedBytecode",
                "evm.methodIdentifiers",
                "evm.gasEstimates",
                "evm.assembly"
              ]
            }
          }
        }
      },
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 50,
          },
          viaIR: true,
          outputSelection: {
            "*": {
              "": ["ast"],
              "*": [
                "abi",
                "metadata",
                "devdoc",
                "userdoc",
                "storageLayout",
                "evm.legacyAssembly",
                "evm.bytecode",
                "evm.deployedBytecode",
                "evm.methodIdentifiers",
                "evm.gasEstimates",
                "evm.assembly"
              ]
            }
          }
        }
      }
    ]
  },
  networks: {
    monad: {
      url: "https://testnet-rpc.monad.xyz", // Replace with actual Monad testnet RPC if different
      chainId: 10143,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    }
  }
};
