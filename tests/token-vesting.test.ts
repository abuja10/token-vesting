import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state
let vestingSchedules = new Map();
let totalTokensLocked = 0;

// Constants for errors
const ERR_NOT_AUTHORIZED = 100;
const ERR_ALREADY_INITIALIZED = 101;
const ERR_NOT_FOUND = 102;
const ERR_INVALID_SCHEDULE = 103;
const ERR_NO_TOKENS_TO_CLAIM = 104;

// Mock variables
let contractOwner: string;
let beneficiary: string;

// Reset state before each test
beforeEach(() => {
  contractOwner = 'SP3FBR2AGKSTPSPRTQ4X9HFD5KV7JS8Y32E1VQ03';
  beneficiary = 'SP2P1A8DTVG3WHEHCWV4KDCZJRHJ2HJJ19C1K34VF';
  vestingSchedules.clear();
  totalTokensLocked = 0;
});

// Mock functions to simulate contract logic
function createVestingSchedule({
  beneficiary,
  totalAmount,
  startBlock,
  cliffLength,
  vestingLength,
  vestingInterval,
  isRevocable,
  sender,
}: {
  beneficiary: string,
  totalAmount: number,
  startBlock: number,
  cliffLength: number,
  vestingLength: number,
  vestingInterval: number,
  isRevocable: boolean,
  sender: string,
}) {
  if (sender !== contractOwner) {
    return { error: ERR_NOT_AUTHORIZED };
  }
  if (vestingSchedules.has(beneficiary)) {
    return { error: ERR_ALREADY_INITIALIZED };
  }
  if (totalAmount <= 0 || vestingLength < cliffLength || vestingInterval <= 0) {
    return { error: ERR_INVALID_SCHEDULE };
  }

  vestingSchedules.set(beneficiary, {
    totalAmount,
    startBlock,
    cliffLength,
    vestingLength,
    vestingInterval,
    tokensClaimed: 0,
    isRevocable,
    isActive: true,
  });

  totalTokensLocked += totalAmount;
  return { success: true };
}
function getClaimableTokens({ beneficiary, currentBlock }: { beneficiary: string, currentBlock: number }) {
  const schedule = vestingSchedules.get(beneficiary);
  if (!schedule || !schedule.isActive) {
    return 0;
  }

  const cliffEnd = schedule.startBlock + schedule.cliffLength;
  if (currentBlock < cliffEnd) {
    return 0;
  }

  const elapsedBlocks = currentBlock - schedule.startBlock;
  const vestedAmount = Math.floor(
    (elapsedBlocks * schedule.totalAmount) / schedule.vestingLength
  );
  return vestedAmount - schedule.tokensClaimed;
}
function claimTokens({ sender }: { sender: string }) {
  const schedule = vestingSchedules.get(sender);
  if (!schedule || !schedule.isActive) {
    return { error: ERR_NOT_FOUND };
  }

  const claimable = getClaimableTokens({ beneficiary: sender, currentBlock: 200 }); // Simulate block height
  if (claimable <= 0) {
    return { error: ERR_NO_TOKENS_TO_CLAIM };
  }

  schedule.tokensClaimed += claimable;
  totalTokensLocked -= claimable;

  return { success: true, claimedAmount: claimable };
}
function revokeSchedule({ beneficiary, sender }: { beneficiary: string, sender: string }) {
  const schedule = vestingSchedules.get(beneficiary);
  if (sender !== contractOwner) {
    return { error: ERR_NOT_AUTHORIZED };
  }
  if (!schedule || !schedule.isRevocable || !schedule.isActive) {
    return { error: ERR_NOT_FOUND };
  }

  schedule.isActive = false;
  const unclaimedTokens = schedule.totalAmount - schedule.tokensClaimed;
  totalTokensLocked -= unclaimedTokens;

  return { success: true, unclaimedTokens };
}
// Tests
describe('Token Vesting Contract', () => {
  it('should allow the owner to create a new vesting schedule', () => {
    const result = createVestingSchedule({
      beneficiary,
      totalAmount: 1000,
      startBlock: 100,
      cliffLength: 50,
      vestingLength: 200,
      vestingInterval: 10,
      isRevocable: true,
      sender: contractOwner,
    });

    expect(result).toEqual({ success: true });
  });

  it('should not allow non-owners to create a vesting schedule', () => {
    const nonOwner = 'SP2H7J8XT6ZMNQRB7CDYTHXPKDHYH6YHG0YY8T6X';
    const result = createVestingSchedule({
      beneficiary,
      totalAmount: 1000,
      startBlock: 100,
      cliffLength: 50,
      vestingLength: 200,
      vestingInterval: 10,
      isRevocable: true,
      sender: nonOwner,
    });

    expect(result).toEqual({ error: ERR_NOT_AUTHORIZED });
  });

  it('should calculate claimable tokens after the cliff period', () => {
    createVestingSchedule({
      beneficiary,
      totalAmount: 1000,
      startBlock: 100,
      cliffLength: 50,
      vestingLength: 200,
      vestingInterval: 10,
      isRevocable: true,
      sender: contractOwner,
    });

    const claimable = getClaimableTokens({ beneficiary, currentBlock: 160 });
    expect(claimable).toBeGreaterThan(0);
  });

  it('should allow a beneficiary to claim vested tokens', () => {
    createVestingSchedule({
      beneficiary,
      totalAmount: 1000,
      startBlock: 100,
      cliffLength: 50,
      vestingLength: 200,
      vestingInterval: 10,
      isRevocable: true,
      sender: contractOwner,
    });

    const result = claimTokens({ sender: beneficiary });
    expect(result.success).toBe(true);
    expect(result.claimedAmount).toBeGreaterThan(0);
  });

  it('should revoke a revocable schedule', () => {
    createVestingSchedule({
      beneficiary,
      totalAmount: 1000,
      startBlock: 100,
      cliffLength: 50,
      vestingLength: 200,
      vestingInterval: 10,
      isRevocable: true,
      sender: contractOwner,
    });

    const result = revokeSchedule({ beneficiary, sender: contractOwner });
    expect(result.success).toBe(true);
    expect(result.unclaimedTokens).toBeGreaterThan(0);
  });
});
