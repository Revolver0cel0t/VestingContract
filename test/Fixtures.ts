
import { Signer } from "ethers";
import { ethers } from "hardhat";
import { RevToken, Vest } from "../typechain-types";

const MAX_UINT_256 = ethers.BigNumber.from(2).pow(256).sub(1);
const tokenPower = ethers.BigNumber.from(10).pow(18);

type SignerWithAddress = Signer  & {address:string}

export async function deployVestFixture() {
    const [owner, otherAccount] = await ethers.getSigners();
  
    const Vest = await ethers.getContractFactory("Vest");
    const RevToken = await ethers.getContractFactory("RevToken");
    const token = await RevToken.deploy();
    const vest = await Vest.deploy(owner.address, token.address);
  
    await token.approveFor(vest.address, otherAccount.address, MAX_UINT_256);
    await token.approveFor(otherAccount.address, vest.address, MAX_UINT_256);
    await token.approveFor(vest.address, owner.address, MAX_UINT_256);
    await token.approveFor(owner.address, vest.address, MAX_UINT_256);
  
    await token.mintToUser(
      vest.address,
      ethers.BigNumber.from("500").mul(tokenPower)
    );
  
    return { vest, token, owner, otherAccount };
}

async function createClaim(vest:Vest, token:RevToken, owner:SignerWithAddress, otherAccount:SignerWithAddress,seconds:number){
    const time = (Date.now() / 1000)
    const params = {
      address: otherAccount.address,
      totalVestedAmount: ethers.BigNumber.from("10").mul(tokenPower),
      claimStart: ethers.BigNumber.from(time.toFixed(0)),
      claimEnd: ethers.BigNumber.from(
        ethers.BigNumber.from((time + seconds).toFixed(0))
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
    console.log("claimee end time",ethers.BigNumber.from((time + seconds).toFixed(0)))
  
    return { vest, token, owner, otherAccount, params };
    
}

export async function createClaimFixture() {
    const { vest, token, owner, otherAccount } = await deployVestFixture();

    return await createClaim(vest, token, owner, otherAccount,15780000)
}


export async function createSmallClaimFixture() {
    const { vest, token, owner, otherAccount } = await deployVestFixture();

    return await createClaim(vest, token, owner, otherAccount,10)
}

export async function revokedClaimFixture() {
    const { vest, token, owner, otherAccount, params } =
      await createClaimFixture();
  
    await vest.removeClaimee(otherAccount.address);
  
    return { vest, token, owner, otherAccount, params };
}
  