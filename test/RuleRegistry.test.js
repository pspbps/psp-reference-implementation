const { expect } = require("chai");

describe("RuleRegistry (PSP v1.0 Reference)", function () {
  async function deploy() {
    const [invocationManager, user] = await ethers.getSigners();

    const feeBps = 40; // 0.40%
    const feeCap = 5_000_000; // e.g., 5 USDC (6 decimals)
    const feeRecipient = invocationManager.address;
    const feeUpdateDelaySeconds = 48 * 60 * 60;

    const RuleRegistry = await ethers.getContractFactory("RuleRegistry");
    const rr = await RuleRegistry.deploy(
      invocationManager.address,
      feeBps,
      feeCap,
      feeRecipient,
      feeUpdateDelaySeconds
    );

    await rr.waitForDeployment();
    return { rr, invocationManager, user };
  }

  it("creates a rule with outcomes summing to 10,000 bps", async function () {
    const { rr, user } = await deploy();

    const outcomes = [
      { kind: 0, bps: 8500, param: 0 },
      { kind: 1, bps: 1500, param: 0 }
    ];

    const tx = await rr.connect(user).createRule(outcomes);
    await tx.wait();

    expect(await rr.nextRuleId()).to.equal(2);
    const rule = await rr.rules(1);
    expect(rule.creator).to.equal(user.address);
  });

  it("pickOutcome is deterministic and recomputable", async function () {
    const { rr, user } = await deploy();

    const outcomes = [
      { kind: 0, bps: 8500, param: 0 },
      { kind: 1, bps: 1500, param: 0 }
    ];
    await (await rr.connect(user).createRule(outcomes)).wait();

    const randomValue = 123456789;
    const idx1 = await rr.pickOutcome(1, randomValue);
    const idx2 = await rr.pickOutcome(1, randomValue);

    expect(idx1).to.equal(idx2);
    expect(idx1).to.be.oneOf([0n, 1n]);
  });

  it("revealWithAmount finalizes exactly once", async function () {
    const { rr, invocationManager, user } = await deploy();

    const outcomes = [
      { kind: 0, bps: 8500, param: 0 },
      { kind: 1, bps: 1500, param: 0 }
    ];
    await (await rr.connect(user).createRule(outcomes)).wait();

    const invocationId = ethers.keccak256(ethers.toUtf8Bytes("invocation-1"));
    const ruleId = 1;
    const asset = ethers.ZeroAddress;
    const amount = 120000000; // e.g., 120 USDC (6 decimals)
    const randomValue = 42;
    const salt = ethers.keccak256(ethers.toUtf8Bytes("salt-1"));

    const commitment = await rr.computeCommitment(
      invocationManager.address,
      invocationId,
      ruleId,
      asset,
      amount,
      randomValue,
      salt
    );

    await (await rr.connect(user).commit(commitment)).wait();

    await (await rr
      .connect(invocationManager)
      .revealWithAmount(invocationId, ruleId, asset, amount, randomValue, salt)).wait();

    await expect(
      rr.connect(invocationManager).revealWithAmount(invocationId, ruleId, asset, amount, randomValue, salt)
    ).to.be.revertedWith("INVOCATION_ALREADY_REVEALED");
  });

  it("fee is deterministic and capped", async function () {
    const { rr } = await deploy();

    // amount that produces fee below cap: 120 * 0.4% = 0.48
    const fee1 = await rr.quoteFee(ethers.ZeroAddress, 120000000);
    expect(fee1).to.equal(480000n);

    // large amount should cap to feeCap
    const fee2 = await rr.quoteFee(ethers.ZeroAddress, 2000000000);
    expect(fee2).to.equal(5000000n);
  });
});
