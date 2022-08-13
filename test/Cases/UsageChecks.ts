import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { createSmallClaimFixture } from "../Fixtures";
import { waitForSeconds } from "../Utils";

const tokenPower = ethers.BigNumber.from(10).pow(18);

export const runUsageChecks = (()=>describe("Advanced Checks", function () {
    it("If we havent reach the end timestamp, we shouldnt get the full amt", async function () {
          const { vest, otherAccount } = await loadFixture(createSmallClaimFixture);
  
          await waitForSeconds(1)
          await vest.accrueRewardsForAccount(otherAccount.address)
          console.log((await vest.getUserClaimAmount(otherAccount.address)).toString(),ethers.BigNumber.from("10000000000000000000").toString())
  
    
          expect((await vest.getUserClaimAmount(otherAccount.address))).to.lessThan(ethers.BigNumber.from("10000000000000000000").toString());
    });

    it("Should get the whole amount after vest period", async function () {
        const { vest, otherAccount } = await loadFixture(createSmallClaimFixture);

        await waitForSeconds(4)
        await vest.accrueRewardsForAccount(otherAccount.address)
        console.log((await vest.getUserClaimAmount(otherAccount.address)).toString(),ethers.BigNumber.from("10000000000000000000").toString())

  
        expect(((await vest.getUserClaimAmount(otherAccount.address))).toString()).to.equal(ethers.BigNumber.from("10000000000000000000").toString());
    });

  }));
