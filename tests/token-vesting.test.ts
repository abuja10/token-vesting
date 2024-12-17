import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state
let vestingSchedules = new Map();
let totalTokensLocked = 0;
let contractPaused = false;


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

// Mock function for modify-vesting-schedule
function modifyVestingSchedule({
  beneficiary,
  newVestingLength,
  newCliffLength,
  sender
}: {
  beneficiary: string,
  newVestingLength: number,
  newCliffLength: number,
  sender: string
}) {
  if (sender !== contractOwner) {
    return { error: ERR_NOT_AUTHORIZED };
  }

  const schedule = vestingSchedules.get(beneficiary);
  if (!schedule || !schedule.isActive) {
    return { error: ERR_NOT_FOUND };
  }

  if (newVestingLength < newCliffLength) {
    return { error: ERR_INVALID_SCHEDULE };
  }

  vestingSchedules.set(beneficiary, {
    ...schedule,
    vestingLength: newVestingLength,
    cliffLength: newCliffLength
  });

  return { success: true };
}

// Mock function for get-vesting-status
function getVestingStatus({ 
  beneficiary, 
  currentBlock 
}: { 
  beneficiary: string, 
  currentBlock: number 
}) {
  const schedule = vestingSchedules.get(beneficiary);
  if (!schedule) {
    return { error: ERR_NOT_FOUND };
  }

  const cliffEnd = schedule.startBlock + schedule.cliffLength;
  const vestingEnd = schedule.startBlock + schedule.vestingLength;

  return {
    success: true,
    status: {
      isActive: schedule.isActive,
      inCliffPeriod: currentBlock < cliffEnd,
      fullyVested: currentBlock >= vestingEnd,
      totalClaimed: schedule.tokensClaimed,
      remainingAmount: schedule.totalAmount - schedule.tokensClaimed
    }
  };
}

// Mock function for toggle-contract-pause
function toggleContractPause({ sender }: { sender: string }) {
  if (sender !== contractOwner) {
    return { error: ERR_NOT_AUTHORIZED };
  }
  contractPaused = !contractPaused;
  return { success: true };
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


describe('Token Vesting Contract - Additional Features', () => {
  it('should allow owner to modify vesting schedule', () => {
    // First create a schedule
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

    const result = modifyVestingSchedule({
      beneficiary,
      newVestingLength: 300,
      newCliffLength: 100,
      sender: contractOwner
    });

    expect(result).toEqual({ success: true });
    
    const schedule = vestingSchedules.get(beneficiary);
    expect(schedule.vestingLength).toBe(300);
    expect(schedule.cliffLength).toBe(100);
  });

  it('should not allow non-owner to modify vesting schedule', () => {
    const nonOwner = 'SP2H7J8XT6ZMNQRB7CDYTHXPKDHYH6YHG0YY8T6X';
    const result = modifyVestingSchedule({
      beneficiary,
      newVestingLength: 300,
      newCliffLength: 100,
      sender: nonOwner
    });

    expect(result).toEqual({ error: ERR_NOT_AUTHORIZED });
  });

  it('should return correct vesting status', () => {
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

    const result = getVestingStatus({ 
      beneficiary, 
      currentBlock: 150 
    });

    expect(result.success).toBe(true);
    if (result.success && result.status) {
      expect(result.status.isActive).toBe(true);
      expect(result.status.inCliffPeriod).toBe(false);
      expect(result.status.fullyVested).toBe(false);
    } else {
      fail('Expected result.status to be defined');
    }
  });

  it('should allow owner to toggle contract pause', () => {
    const result = toggleContractPause({ 
      sender: contractOwner 
    });

    expect(result).toEqual({ success: true });
    expect(contractPaused).toBe(true);

    // Toggle back
    const secondResult = toggleContractPause({ 
      sender: contractOwner 
    });
    
    expect(secondResult).toEqual({ success: true });
    expect(contractPaused).toBe(false);
  });

  it('should not allow non-owner to toggle contract pause', () => {
    const nonOwner = 'SP2H7J8XT6ZMNQRB7CDYTHXPKDHYH6YHG0YY8T6X';
    const result = toggleContractPause({ 
      sender: nonOwner 
    });

    expect(result).toEqual({ error: ERR_NOT_AUTHORIZED });
  });
});
function fail(arg0: string) {
  throw new Error('Function not implemented.');
}

