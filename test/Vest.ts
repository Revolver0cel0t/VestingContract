import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

const MAX_UINT_256 = ethers.BigNumber.from(2).pow(256).sub(1);

describe("Vest", function () {
  async function deployVestFixture() {
    const [owner, otherAccount] = await ethers.getSigners();

    const Vest = await ethers.getContractFactory("Vest");
    const RevToken = await ethers.getContractFactory("RevToken");
    const token = await RevToken.deploy();
    const vest = await Vest.deploy(owner.address, token.address);

    await token.approveFor(vest.address, otherAccount.address, MAX_UINT_256);
    await token.approveFor(otherAccount.address, vest.address, MAX_UINT_256);
    await token.approveFor(vest.address, owner.address, MAX_UINT_256);
    await token.approveFor(owner.address, vest.address, MAX_UINT_256);

    await token.mintToUser(vest.address, ethers.BigNumber.from("500").pow(18));

    return { vest, token, owner, otherAccount };
  }

  async function createClaimFixture() {
    const { vest, token, owner, otherAccount } = await deployVestFixture();
    const params = {
      address: otherAccount.address,
      totalVestedAmount: ethers.BigNumber.from("10").pow(18),
      claimStart: ethers.BigNumber.from((Date.now() / 1000).toFixed(0)),
      claimEnd: ethers.BigNumber.from(
        ethers.BigNumber.from((Date.now() / 1000 + 15780000).toFixed(0))
      ),
      cliffEnd: ethers.BigNumber.from(0),
    };

    // await token
    await vest.addClaimee(
      params.address,
      params.totalVestedAmount,
      params.claimEnd,
      params.claimStart,
      params.cliffEnd
    );

    return { vest, token, owner, otherAccount };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { vest, owner } = await loadFixture(deployVestFixture);

      expect(await vest.getOwner()).to.equal(owner.address);
    });

    it("Should set the right token address", async function () {
      const { vest, token } = await loadFixture(deployVestFixture);

      expect(await vest.claimToken()).to.equal(token.address);
    });

    it("Should set the right params when creating a claim", async function () {
      const { vest, otherAccount } = await loadFixture(deployVestFixture);

      const params = {
        address: otherAccount.address,
        totalVestedAmount: ethers.BigNumber.from("10").pow(18),
        claimStart: ethers.BigNumber.from((Date.now() / 1000).toFixed(0)),
        claimEnd: ethers.BigNumber.from(
          ethers.BigNumber.from((Date.now() / 1000 + 15780000).toFixed(0))
        ),
        cliffEnd: ethers.BigNumber.from(0),
      };

      // await token
      await vest.addClaimee(
        params.address,
        params.totalVestedAmount,
        params.claimEnd,
        params.claimStart,
        params.cliffEnd
      );
      const returnedParams = await vest.getUserClaimData(otherAccount.address);
      expect(returnedParams.totalVestedAmount).to.equal(
        params.totalVestedAmount
      );
      expect(returnedParams.claimStart).to.equal(params.claimStart);
      expect(returnedParams.claimEnd).to.equal(params.claimEnd);
      expect(returnedParams.cliffEnd).to.equal(params.cliffEnd);
    });
    it("Claimable amount should increase after a few seconds", function (done) {
      this.timeout(4500);

      setTimeout(function () {
        loadFixture(deployVestFixture).then(({ vest, otherAccount }) => {
          const params = {
            address: otherAccount.address,
            totalVestedAmount: ethers.BigNumber.from("10").pow(18),
            claimStart: ethers.BigNumber.from((Date.now() / 1000).toFixed(0)),
            claimEnd: ethers.BigNumber.from(
              ethers.BigNumber.from((Date.now() / 1000 + 15780000).toFixed(0))
            ),
            cliffEnd: ethers.BigNumber.from(0),
          };

          return vest
            .addClaimee(
              params.address,
              params.totalVestedAmount,
              params.claimEnd,
              params.claimStart,
              params.cliffEnd
            )
            .then(async () => {
              return vest.accrueRewardsForAccount(params.address);
            })
            .then(async () => {
              return vest.getUserClaimAmount(otherAccount.address);
            })
            .then((returnedParams) => {
              if (!returnedParams.gt(0)) {
                done("Returned amount not greater than 0");
              } else {
                done();
              }
            });
        });
      }, 3000);
    });

    it("When withdraw amount <= balance - totalClaimable,success", async function () {
      const { vest, otherAccount } = await loadFixture(createClaimFixture);

      await vest.withdrawTokens(
        ethers.BigNumber.from("200").pow(18),
        otherAccount.address
      );
    });
    it("When withdraw amount > balance - totalClaimable,failure", async function () {
      const { vest, otherAccount } = await loadFixture(createClaimFixture);

      await expect(
        vest.withdrawTokens(
          ethers.BigNumber.from("500").pow(18),
          otherAccount.address
        )
      ).to.be.reverted;
    });
  });
});
