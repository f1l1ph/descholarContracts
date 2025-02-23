# Makefile for descholar

EDU_RPC_TESTNET = https://rpc.open-campus-codex.gelato.digital
EDU_RPC_MAINNET = https://rpc.edu-chain.raas.gelato.cloud

SEPOLIA_TESTNET_RPC = https://eth-sepolia.g.alchemy.com/v2/demo

.PHONY: deploy_testnet deploy_mainnet

deploy_testnet:
	@echo "Deploying to testnet"
	forge fmt
	forge clean
	forge build  
	## !change constructor args to your own
	forge create --rpc-url $(EDU_RPC_TESTNET) --private-key $(PRIVATE_KEY) src/descholar.sol:Descholar --broadcast --constructor-args 0x6486795CD89D7439090c3906b4C9ebd4a59b4c40

deploy_mainnet:
	@echo "Deploying to mainnet"
	forge fmt
	forge clean
	forge build
	forge create --rpc-url $(EDU_RPC_MAINNET) --private-key $(PRIVATE_KEY) ./src/descholar.sol:Descholar --broadcast --constructor-args $(PUBLIC_KEY)