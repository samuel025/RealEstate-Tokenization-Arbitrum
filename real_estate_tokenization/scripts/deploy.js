const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const RealEstateToken = await hre.ethers.getContractFactory("RealEstateToken");
  
  // Replace this with a real ERC20 token address on Arbitrum Sepolia
  const paymentTokenAddress = "0x1b6bD63ed6985899049695b210c34eBd49Fba9d1";

  const realEstateToken = await RealEstateToken.deploy(paymentTokenAddress);

  console.log("RealEstateToken address:", await realEstateToken.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });