import { ethers } from "hardhat";

async function main() {
  const RESContract = await ethers.getContractFactory("RES_TOKEN");
  const resContract = await RESContract.deploy("RES NFT", "RES");

  console.log(`res deployed at ${resContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
