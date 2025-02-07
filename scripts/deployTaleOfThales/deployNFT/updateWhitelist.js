const { ethers } = require('hardhat');
const { getTargetAddress, txLog } = require('../../helpers');
const w3utils = require('web3-utils');
const ITEMS_METADATA = require('./taleOfThalesNFTMeta.json');
const { assert } = require('../../../test/utils/common');

async function main() {
	let accounts = await ethers.getSigners();
	let owner = accounts[0];
	let networkObj = await ethers.provider.getNetwork();
	let network = networkObj.name;
	let ToTNFTContract;
	let totNFTAddress;

	if (network === 'unknown') {
		network = 'localhost';
	}

	if (network == 'homestead') {
		network = 'mainnet';
	}

	if (networkObj.chainId == 69) {
		networkObj.name = 'optimisticKovan';
		network = 'optimisticKovan';
	}
	if (networkObj.chainId == 10) {
		networkObj.name = 'optimisticEthereum';
		network = 'optimisticEthereum';
	}
	if (networkObj.chainId == 80001) {
		networkObj.name = 'polygonMumbai';
		network = 'polygonMumbai';
	}

	if (networkObj.chainId == 137) {
		networkObj.name = 'polygon';
		network = 'polygon';
	}

	if (networkObj.chainId == 420) {
		networkObj.name = 'optimisticGoerli';
		network = 'optimisticGoerli';
	}

	if (networkObj.chainId == 5) {
		networkObj.name = 'goerli';
		network = 'goerli';
	}

	console.log('Account is: ' + owner.address);
	console.log('Network:' + network);
	console.log('Network id:' + networkObj.chainId);

	/* ========== PROPERTIES ========== */

	// CHANGE addresses
	const whitelist = [
		'0x088cda4c48750442548ab476af5eea7135394063',
		'0x884E6b3e3C86035e47319A550e69189DFfb7200b',
	];

	ToTNFTContract = await ethers.getContractFactory('TaleOfThalesNFTs');
	totNFTAddress = getTargetAddress('TaleOfThalesNFTs', network);
	console.log('Found ToTNFTContract at:', totNFTAddress);

	const taleOfThales = await ToTNFTContract.attach(totNFTAddress);

	console.log('Script starts');
	console.log('-------------------------------------------------------');

	try {
		const collectionIndex = 1;
		const flag = true;

		const txUpdateWhitelist = await taleOfThales.updateWhitelistForCollection(
			collectionIndex,
			whitelist,
			flag
		);

		await txUpdateWhitelist.wait().then((e) => {
			txLog(txUpdateWhitelist, `Updated whitelist for collection index ${collectionIndex}`);
		});
	} catch (e) {
		console.log('Error ', e);
	}
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
