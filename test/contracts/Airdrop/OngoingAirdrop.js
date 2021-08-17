const { deploymentFixture, getReward } = require('./ongoingAirdropFixture');
const { assert } = require('../../utils/common');
const { currentTime, fastForward } = require('../../utils')();
const YEAR = 31556926;

// OngoindAirdrop tests
describe('Contract: OndoingAirdrop', async () => {
	let acc1, acc2, ongoingAirdrop, merkleTree, snapshot, snapshotHashes;

	beforeEach(async () => {
		({
			acc1,
			acc2,
			ongoingAirdrop,
			token,
			merkleTree,
			snapshot,
			snapshotHashes,
		} = await deploymentFixture());
	});

	describe('Ongoing Airdrop rewards', async () => {
		it('snapshot user should be able to retrieve reward', async () => {
			await getReward(1, merkleTree, snapshot, snapshotHashes, ongoingAirdrop, acc1);
		}),
			it("snapshot user shouldn't be able to retrieve reward twice", async () => {
				await getReward(1, merkleTree, snapshot, snapshotHashes, ongoingAirdrop, acc1);
				await assert.revert(
					getReward(1, merkleTree, snapshot, snapshotHashes, ongoingAirdrop, acc1),
					'Tokens have already been claimed'
				);
			}),
			it("account different from airdrop recipient shouldn't be able to retrieve reward", async () => {
				await assert.revert(
					getReward(1, merkleTree, snapshot, snapshotHashes, ongoingAirdrop, acc2),
					'The reward recipient should be the transaction sender'
				);
			}),
			it("account shouldn't be able to retrieve reward with invalid merkle proof", async () => {
				// Assign the wrong hash to 1st index in order to generate invalid merkle proof
				snapshotHashes[1] = snapshotHashes[0];

				await assert.revert(
					getReward(1, merkleTree, snapshot, snapshotHashes, ongoingAirdrop, acc1),
					'Proof is not valid'
				);
			});

		it('self destruct before time', async () => {
			await assert.revert(
				ongoingAirdrop._selfDestruct(acc1.address),
				'Contract can only be selfdestruct after a year'
			);
		});

		it('self destruct', async () => {
			fastForward(YEAR);
			await ongoingAirdrop._selfDestruct(acc1.address);
			let balance = await token.balanceOf(ongoingAirdrop.address);
			assert.equal(balance, 0);
		});
	});
});