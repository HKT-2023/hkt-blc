import { ethers } from "hardhat";

async function main() {
  const MarketplaceContract = await ethers.getContractFactory(
    "RES_Marketplace"
  );
  const marketplaceContract = await MarketplaceContract.deploy();

  console.log(`marketplace deployed at ${marketplaceContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
