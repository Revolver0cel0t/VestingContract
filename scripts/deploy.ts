import { ethers } from "hardhat";

async function main() {
  const Vest = await ethers.getContractFactory("Vest");
  const RevToken = await ethers.getContractFactory("RevToken");
  const token = await RevToken.deploy();
  const vest = await Vest.deploy(
    "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199",
    token.address
  );

  await vest.deployed();

  console.log(`Contract deployred!`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
