import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployVestFixture,createClaimFixture,revokedClaimFixture } from "../Fixtures";

const tokenPower = ethers.BigNumber.from(10).pow(18);

export const runBaseChecks = (()=>describe("Base Checks", function () {

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
          totalVestedAmount: ethers.BigNumber.from("10").mul(tokenPower),
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
  
          loadFixture(createClaimFixture).then(
            ({ vest, otherAccount, params }) => {
              return vest
                .accrueRewardsForAccount(params.address)
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
            }
          );
      });
  
      it("Claiming should send tokens", function (done) {
        this.timeout(4500);
  
          loadFixture(createClaimFixture).then(
            ({ vest, otherAccount, params, token }) => {
              return vest
                .accrueRewardsForAccount(params.address)
                .then(async () => {
                  return vest.withdrawAccruedTokens(otherAccount.address);
                })
                .then(() => {
                  return token.balanceOf(otherAccount.address);
                })
                .then((returnedParams) => {
                  if (!returnedParams.gt(0)) {
                    done("Returned amount not greater than 0");
                  } else {
                    done();
                  }
                });
            }
          );
      });
  
      it("When withdraw amount <= balance - totalClaimable,success", async function () {
        const { vest, otherAccount } = await loadFixture(createClaimFixture);
  
        await vest.withdrawTokens(
          ethers.BigNumber.from("200").mul(tokenPower),
          otherAccount.address
        );
      });
  
      it("When withdraw amount > balance - totalClaimable,failure", async function () {
        const { vest, otherAccount } = await loadFixture(createClaimFixture);
  
        await expect(
          vest.withdrawTokens(
            ethers.BigNumber.from("500").mul(tokenPower),
            otherAccount.address
          )
        ).to.be.reverted;
      });
  
      it("When claim is revoked, claimInvalid must be equal to true", async function () {
        const { vest, otherAccount } = await loadFixture(revokedClaimFixture);
  
        const claimeeData = await vest.getUserClaimData(otherAccount.address);
        expect(claimeeData.claimInvalid).to.equal(true);
      });
  
      it("When claim is revoked, cannot access updater functions", async function () {
        const { vest, otherAccount } = await loadFixture(revokedClaimFixture);
        expect(
          vest.changeTotalVestedAmount(
            otherAccount.address,
            ethers.BigNumber.from(10).mul(tokenPower)
          )
        ).to.be.reverted;
        expect(
          vest.changeVestPeriod(
            otherAccount.address,
            ethers.BigNumber.from(10).mul(tokenPower)
          )
        ).to.be.reverted;
        expect(
          vest.changeCliff(
            otherAccount.address,
            ethers.BigNumber.from(10).mul(tokenPower)
          )
        ).to.be.reverted;
      });
  
      it("Update claim amount function", async function () {
        const { vest, otherAccount } = await loadFixture(createClaimFixture);
  
        const claimData = await vest.getUserClaimData(otherAccount.address);
        await vest.changeTotalVestedAmount(
          otherAccount.address,
          ethers.BigNumber.from(495).mul(tokenPower)
        );
        const newClaimData = await vest.getUserClaimData(otherAccount.address);
        expect(newClaimData.totalVestedAmount).to.greaterThan(
          claimData.totalVestedAmount
        );
      });
  
      it("Update claim duration function", async function () {
        const { vest, otherAccount } = await loadFixture(createClaimFixture);
  
        const claimData = await vest.getUserClaimData(otherAccount.address);
        await vest.changeVestPeriod(
          otherAccount.address,
          ethers.BigNumber.from(495).mul(tokenPower)
        );
        const newClaimData = await vest.getUserClaimData(otherAccount.address);
        expect(newClaimData.claimEnd).to.greaterThan(claimData.claimEnd);
      });
  
      it("Cliff cant be set if not set previously", async function () {
        const { vest, otherAccount } = await loadFixture(createClaimFixture);
  
        expect(
          vest.changeVestPeriod(
            otherAccount.address,
            ethers.BigNumber.from(495).mul(tokenPower)
          )
        ).to.be.reverted;
      });
    
  }));
