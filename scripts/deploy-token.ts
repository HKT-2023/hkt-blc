import { ethers } from "hardhat";

async function main() {
  const ResTokenContract = await ethers.getContractFactory("RES_TOKEN");
  const resTokenContract = await ResTokenContract.deploy("RES Token", "RESTK");

  console.log(`res token deployed at ${resTokenContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
