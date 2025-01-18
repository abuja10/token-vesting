import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state
let totalTokensLocked: number;
let vestingSchedules: Record<string, any>;
let contractOwner: string;

beforeEach(() => {
  // Reset the state before each test
  totalTokensLocked = 10000; // Simulate some tokens already locked
  vestingSchedules = {};
  contractOwner = 'owner';
});

// Helper functions to simulate contract methods
function emergencyWithdraw(amount: number, sender: string) {
  if (sender !== contractOwner) return { ok: false, error: 100 }; // ERR-NOT-AUTHORIZED
  if (amount > totalTokensLocked) return { ok: false, error: 105 }; // ERR-NO-BALANCE

  totalTokensLocked -= amount;
  return { ok: amount };
}

function createSingleSchedule(
  beneficiary: string,
  amount: number,
  startBlock: number,
  cliffLength: number,
  vestingLength: number,
  vestingInterval: number,
  isRevocable: boolean
) {
  if (vestingSchedules[beneficiary]) return { ok: false, error: 107 }; // ERR-SCHEDULE-EXISTS

  vestingSchedules[beneficiary] = {
    amount,
    startBlock,
    cliffLength,
    vestingLength,
    vestingInterval,
    isRevocable,
    isActive: true,
  };
  return { ok: true };
}

function transferVestingSchedule(from: string, to: string, sender: string) {
  if (sender !== contractOwner) return { ok: false, error: 100 }; // ERR-NOT-AUTHORIZED
  const schedule = vestingSchedules[from];
  if (!schedule) return { ok: false, error: 104 }; // ERR-NOT-FOUND
  if (!schedule.isActive) return { ok: false, error: 104 }; // ERR-NOT-FOUND

  delete vestingSchedules[from];
  vestingSchedules[to] = schedule;
  return { ok: true };
}

// Tests
describe('Emergency Withdraw Tests', () => {
  it('should allow the owner to withdraw tokens in an emergency', () => {
    const result = emergencyWithdraw(5000, 'owner');
    expect(result.ok).toBe(5000);
    expect(totalTokensLocked).toBe(5000); // Remaining balance
  });

  it('should prevent non-owner from withdrawing tokens', () => {
    const result = emergencyWithdraw(5000, 'non-owner');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100); // ERR-NOT-AUTHORIZED
  });

  it('should prevent withdrawal if balance is insufficient', () => {
    const result = emergencyWithdraw(15000, 'owner');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(105); // ERR-NO-BALANCE
  });
});

describe('Vesting Schedule Creation Tests', () => {
  it('should create a new vesting schedule successfully', () => {
    const result = createSingleSchedule(
      'user1',
      1000,
      10,
      5,
      20,
      5,
      true
    );
    expect(result.ok).toBe(true);
    expect(vestingSchedules['user1']).toMatchObject({
      amount: 1000,
      startBlock: 10,
      cliffLength: 5,
      vestingLength: 20,
      vestingInterval: 5,
      isRevocable: true,
      isActive: true,
    });
  });

  it('should prevent creating a schedule for the same beneficiary twice', () => {
    createSingleSchedule('user1', 1000, 10, 5, 20, 5, true);
    const result = createSingleSchedule('user1', 500, 15, 5, 10, 2, false);
    expect(result.ok).toBe(false);
    expect(result.error).toBe(107); // ERR-SCHEDULE-EXISTS
  });
});

describe('Vesting Schedule Transfer Tests', () => {
  it('should transfer a vesting schedule to a new beneficiary', () => {
    createSingleSchedule('user1', 1000, 10, 5, 20, 5, true);
    const result = transferVestingSchedule('user1', 'user2', 'owner');
    expect(result.ok).toBe(true);
    expect(vestingSchedules['user1']).toBeUndefined();
    expect(vestingSchedules['user2']).toMatchObject({
      amount: 1000,
      startBlock: 10,
      cliffLength: 5,
      vestingLength: 20,
      vestingInterval: 5,
      isRevocable: true,
      isActive: true,
    });
  });

  it('should prevent transfer by a non-owner', () => {
    createSingleSchedule('user1', 1000, 10, 5, 20, 5, true);
    const result = transferVestingSchedule('user1', 'user2', 'non-owner');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100); // ERR-NOT-AUTHORIZED
  });

  it('should prevent transferring a non-existent vesting schedule', () => {
    const result = transferVestingSchedule('user1', 'user2', 'owner');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(104); // ERR-NOT-FOUND
  });
});
