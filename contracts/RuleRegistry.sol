// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RuleRegistry (PSP v1.0 Reference)
/// @notice Reference implementation for deterministic, verifiable probabilistic settlement.
/// @dev This is NOT a production deployment. It is a reference for education/testing.
///      Authority for protocol definition is the PSP specification repository.
///
/// Core guarantees:
/// - Outcomes are selected deterministically from a 10,000 bps distribution.
/// - Randomness follows a commit–reveal flow.
/// - Each invocation is finalized at most once (no retroactive mutation).
/// - Fee computation is deterministic with a hard cap and timelocked updates.
contract RuleRegistry {
    // -------------------------
    // Admin / Roles
    // -------------------------

    /// @notice Invocation manager allowed to finalize reveals that store outcome + fee metadata.
    address public invocationManager;

    modifier onlyInvocationManager() {
        require(msg.sender == invocationManager, "ONLY_INVOCATION_MANAGER");
        _;
    }

    // -------------------------
    // Rule Model
    // -------------------------

    /// @notice Outcome kind is intentionally generic. Interpretation is application-layer.
    /// @dev Examples (non-normative): full settlement, zero settlement, proportional settlement, etc.
    struct Outcome {
        uint8 kind;       // Generic outcome identifier (application-defined)
        uint16 bps;       // Probability weight; total across outcomes MUST equal 10,000
        uint256 param;    // Generic parameter (application-defined)
    }

    struct Rule {
        address creator;
        uint16 outcomeCount;
    }

    uint256 public nextRuleId = 1;
    mapping(uint256 => Rule) public rules;
    mapping(uint256 => Outcome[]) private ruleOutcomes;

    event RuleCreated(uint256 indexed ruleId, address indexed creator);

    // -------------------------
    // Commit–Reveal (Minimal)
    // -------------------------

    /// @notice Commitments are global (anyone can commit). Reveal is restricted to invocationManager.
    mapping(bytes32 => bool) public committed;

    event Committed(address indexed committer, bytes32 commitment);
    event Revealed(address indexed revealer, bytes32 indexed invocationId, uint256 randomValue, bytes32 commitment);

    function commit(bytes32 commitment) external {
        require(!committed[commitment], "COMMIT_EXISTS");
        committed[commitment] = true;
        emit Committed(msg.sender, commitment);
    }

    // -------------------------
    // Fee Model (Protocol-Level)
    // -------------------------

    /// @notice Fee basis points (e.g., 40 = 0.40%).
    uint16 public feeBps;

    /// @notice Fee cap in "asset minor units" (e.g., USDC has 6 decimals).
    uint256 public feeCap;

    /// @notice Recipient of protocol fees (enforced at execution layer; here we only compute).
    address public feeRecipient;

    // Timelock for fee updates
    uint256 public feeUpdateDelaySeconds;

    struct PendingFeeUpdate {
        uint16 newFeeBps;
        uint256 newFeeCap;
        address newFeeRecipient;
        uint256 eta;
        bool exists;
    }

    PendingFeeUpdate public pendingFeeUpdate;

    event FeeQuoted(address indexed caller, address indexed asset, uint256 amount, uint256 feeCharged);
    event FeeUpdateScheduled(uint16 newFeeBps, uint256 newFeeCap, address newFeeRecipient, uint256 eta);
    event FeeUpdateExecuted(uint16 newFeeBps, uint256 newFeeCap, address newFeeRecipient);

    function quoteFee(address asset, uint256 amount) public view returns (uint256 feeCharged) {
        // asset is included for interface completeness; the fee math uses amount units directly.
        // Execution layer must interpret/transfer accordingly.
        (asset);

        uint256 raw = (amount * uint256(feeBps)) / 10_000;
        if (raw > feeCap) return feeCap;
        return raw;
    }

    function emitFeeQuote(address asset, uint256 amount) external returns (uint256 feeCharged) {
        feeCharged = quoteFee(asset, amount);
        emit FeeQuoted(msg.sender, asset, amount, feeCharged);
    }

    function scheduleFeeUpdate(uint16 newFeeBps, uint256 newFeeCap, address newFeeRecipient) external onlyInvocationManager {
        uint256 eta = block.timestamp + feeUpdateDelaySeconds;
        pendingFeeUpdate = PendingFeeUpdate({
            newFeeBps: newFeeBps,
            newFeeCap: newFeeCap,
            newFeeRecipient: newFeeRecipient,
            eta: eta,
            exists: true
        });
        emit FeeUpdateScheduled(newFeeBps, newFeeCap, newFeeRecipient, eta);
    }

    function executeFeeUpdate() external onlyInvocationManager {
        require(pendingFeeUpdate.exists, "NO_PENDING_UPDATE");
        require(block.timestamp >= pendingFeeUpdate.eta, "TIMELOCK_NOT_EXPIRED");

        feeBps = pendingFeeUpdate.newFeeBps;
        feeCap = pendingFeeUpdate.newFeeCap;
        feeRecipient = pendingFeeUpdate.newFeeRecipient;

        emit FeeUpdateExecuted(feeBps, feeCap, feeRecipient);
        delete pendingFeeUpdate;
    }

    // -------------------------
    // Invocation Finalization
    // -------------------------

    /// @notice Per-invocation finalized outcome index. (0..n-1)
    mapping(bytes32 => uint16) public invocationOutcomeIndex;

    /// @notice Per-invocation finalized settlement input amount.
    mapping(bytes32 => uint256) public invocationAmount;

    /// @notice Per-invocation finalized asset address (0x0 can mean "native" in some integrations).
    mapping(bytes32 => address) public invocationAsset;

    /// @notice Per-invocation finalized protocol fee charged (computed deterministically).
    mapping(bytes32 => uint256) public invocationFeeCharged;

    /// @notice Prevent double-finalization.
    mapping(bytes32 => bool) public invocationFinalized;

    event OutcomeFinalized(
        bytes32 indexed invocationId,
        uint256 indexed ruleId,
        address indexed asset,
        uint256 amount,
        uint16 outcomeIndex,
        uint256 feeCharged
    );

    // -------------------------
    // Constructor
    // -------------------------

    constructor(
        address _invocationManager,
        uint16 _feeBps,
        uint256 _feeCap,
        address _feeRecipient,
        uint256 _feeUpdateDelaySeconds
    ) {
        invocationManager = _invocationManager;
        feeBps = _feeBps;
        feeCap = _feeCap;
        feeRecipient = _feeRecipient;
        feeUpdateDelaySeconds = _feeUpdateDelaySeconds;
    }

    // -------------------------
    // Rule Management
    // -------------------------

    function createRule(Outcome[] calldata outcomes) external returns (uint256 ruleId) {
        require(outcomes.length > 0, "NO_OUTCOMES");

        uint256 sum;
        for (uint256 i = 0; i < outcomes.length; i++) {
            sum += outcomes[i].bps;
        }
        require(sum == 10_000, "BPS_NOT_10000");

        ruleId = nextRuleId;
        nextRuleId = nextRuleId + 1;

        rules[ruleId] = Rule({creator: msg.sender, outcomeCount: uint16(outcomes.length)});

        for (uint256 i = 0; i < outcomes.length; i++) {
            ruleOutcomes[ruleId].push(outcomes[i]);
        }

        emit RuleCreated(ruleId, msg.sender);
    }

    function getOutcome(uint256 ruleId, uint16 idx) external view returns (Outcome memory) {
        require(idx < ruleOutcomes[ruleId].length, "IDX_OOB");
        return ruleOutcomes[ruleId][idx];
    }

    function outcomeCount(uint256 ruleId) external view returns (uint256) {
        return ruleOutcomes[ruleId].length;
    }

    /// @notice Deterministically selects an outcome index using cumulative traversal.
    function pickOutcome(uint256 ruleId, uint256 randomValue) public view returns (uint16) {
        uint256 n = ruleOutcomes[ruleId].length;
        require(n > 0, "RULE_NOT_FOUND");

        uint256 r = randomValue % 10_000; // 0..9999
        uint256 acc;

        for (uint16 i = 0; i < n; i++) {
            acc += ruleOutcomes[ruleId][i].bps;
            if (r < acc) return i;
        }

        // Should never happen when sum == 10,000
        return uint16(n - 1);
    }

    // -------------------------
    // Commitment Verification Helper
    // -------------------------

    /// @notice Commitment binds (invocationManager, invocationId, ruleId, asset, amount, randomValue, salt).
    /// @dev Anyone can verify off-chain or on-chain to check a reveal matches a prior commitment.
    function computeCommitment(
        address _invocationManager,
        bytes32 invocationId,
        uint256 ruleId,
        address asset,
        uint256 amount,
        uint256 randomValue,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_invocationManager, invocationId, ruleId, asset, amount, randomValue, salt));
    }

    function verifyInvocationInputs(
        bytes32 commitment,
        address _invocationManager,
        bytes32 invocationId,
        uint256 ruleId,
        address asset,
        uint256 amount,
        uint256 randomValue,
        bytes32 salt
    ) external view returns (bool) {
        if (!committed[commitment]) return false;
        bytes32 recomputed = computeCommitment(_invocationManager, invocationId, ruleId, asset, amount, randomValue, salt);
        return recomputed == commitment;
    }

    // -------------------------
    // Reveal + Finalize (Invocation Manager Only)
    // -------------------------

    /// @notice Reveals randomness and finalizes an invocation by storing outcomeIndex and fee metadata.
    /// @dev This function does NOT transfer assets. Execution belongs to the application layer.
    function revealWithAmount(
        bytes32 invocationId,
        uint256 ruleId,
        address asset,
        uint256 amount,
        uint256 randomValue,
        bytes32 salt
    ) external onlyInvocationManager returns (uint16 outcomeIndex, uint256 feeCharged, bytes32 commitment) {
        require(!invocationFinalized[invocationId], "INVOCATION_ALREADY_REVEALED");

        commitment = computeCommitment(msg.sender, invocationId, ruleId, asset, amount, randomValue, salt);
        require(committed[commitment], "NO_COMMIT");

        emit Revealed(msg.sender, invocationId, randomValue, commitment);

        outcomeIndex = pickOutcome(ruleId, randomValue);
        feeCharged = quoteFee(asset, amount);

        invocationFinalized[invocationId] = true;
        invocationOutcomeIndex[invocationId] = outcomeIndex;
        invocationAsset[invocationId] = asset;
        invocationAmount[invocationId] = amount;
        invocationFeeCharged[invocationId] = feeCharged;

        emit OutcomeFinalized(invocationId, ruleId, asset, amount, outcomeIndex, feeCharged);
    }
}
