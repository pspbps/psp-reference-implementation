// PSP v1.0 Reference - Minimal deployment script
// Intended for Hardhat runtime: `npx hardhat run scripts/deploy.js --network <network>`

async function main() {
  const [deployer] = await ethers.getSigners();

  // For local testing, we set invocationManager to deployer.
  const invocationManager = deployer.address;

  // Default fee params (non-normative)
  const feeBps = 40; // 0.40%
  const feeCap = 5_000_000; // e.g., 5 USDC if 6 decimals
  const feeRecipient = deployer.address;
  const feeUpdateDelaySeconds = 48 * 60 * 60; // 48 hours

  const RuleRegistry = await ethers.getContractFactory("RuleRegistry");
  const rr = await RuleRegistry.deploy(
    invocationManager,
    feeBps,
    feeCap,
    feeRecipient,
    feeUpdateDelaySeconds
  );

  await rr.waitForDeployment();

  console.log("Deployer:", deployer.address);
  console.log("RuleRegistry deployed to:", await rr.getAddress());
  console.log("invocationManager:", await rr.invocationManager());
  console.log("feeBps:", await rr.feeBps());
  console.log("feeCap:", (await rr.feeCap()).toString());
  console.log("feeRecipient:", await rr.feeRecipient());
  console.log("feeUpdateDelaySeconds:", (await rr.feeUpdateDelaySeconds()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
