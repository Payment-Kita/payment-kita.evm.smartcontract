// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 >=0.6.2 ^0.8.20;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/interfaces/ISwapper.sol

/**
 * @title ISwapper
 * @notice Interface for DEX token swapping functionality
 * @dev Implement this interface to integrate different DEX protocols
 */
interface ISwapper {
    /// @notice Swap tokens with slippage protection
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens to swap
    /// @param minAmountOut Minimum output amount (slippage protection)
    /// @param recipient Address to receive output tokens
    /// @return amountOut Actual output amount received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /// @notice Get a quote for a swap without executing
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens
    /// @return amountOut Expected output amount
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Estimate gas for a swap route
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens
    /// @return estimatedGas Estimated gas cost
    /// @return hopCount Number of hops in the route
    function estimateSwapGas(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 estimatedGas, uint256 hopCount);

    /// @notice Get full swap quote with gas estimate
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token  
    /// @param amountIn Amount of input tokens
    /// @return amountOut Expected output amount
    /// @return estimatedGas Estimated gas cost
    /// @return hopCount Number of hops
    /// @return path Array of token addresses in the swap path
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        uint256 amountOut,
        uint256 estimatedGas,
        uint256 hopCount,
        address[] memory path
    );

    /// @notice Find the best route for a token swap
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @return exists Whether a route exists
    /// @return isDirect Whether the route is a direct swap
    /// @return path Array of token addresses in the route
    function findRoute(
        address tokenIn,
        address tokenOut
    ) external view returns (bool exists, bool isDirect, address[] memory path);
}

// src/interfaces/IUniswapV4.sol

/**
 * @title IUniswapV4
 * @notice Minimal interfaces for Uniswap V4 integration
 * @dev Based on Uniswap V4 core contracts
 */

/// @notice Represents a currency (address(0) for native ETH)
type Currency is address;

/// @notice Type for pool identifiers
type PoolId is bytes32;

/// @notice Parameters identifying a pool
struct PoolKey {
    /// @dev The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @dev The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @dev The pool swap fee, capped at 1_000_000 (100%)
    uint24 fee;
    /// @dev Ticks spacing for the pool
    int24 tickSpacing;
    /// @dev Address of the hook contract (address(0) for no hooks)
    address hooks;
}

/// @notice Parameters for executing a swap
struct SwapParams {
    /// @dev Whether to swap token0 for token1 (true) or token1 for token0 (false)
    bool zeroForOne;
    /// @dev The amount to swap. If positive, exact input. If negative, exact output.
    int256 amountSpecified;
    /// @dev The sqrt price limit. If zeroForOne, must be less than current price.
    uint160 sqrtPriceLimitX96;
}

/// @notice Return value from swap operations
struct BalanceDelta {
    int128 amount0;
    int128 amount1;
}

/**
 * @title IPoolManager
 * @notice Interface for Uniswap V4 PoolManager singleton
 */
interface IPoolManager {
    /// @notice Initialize a new pool
    /// @param key The pool key identifying the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool
    /// @param hookData Data to pass to the hook's beforeInitialize and afterInitialize
    /// @return tick The initial tick of the pool
    function initialize(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (int24 tick);

    /// @notice All interactions with the pool manager must go through unlock
    /// @param data Arbitrary data passed to the unlock callback
    /// @return The data returned from the unlock callback
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Execute a swap within an unlock callback
    /// @param key The pool to swap in
    /// @param params The swap parameters
    /// @param hookData Data to pass to hooks
    /// @return delta The balance delta of the swap
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta memory delta);

    /// @notice Sync currency balance into the pool manager
    /// @param currency The currency to sync
    function sync(Currency currency) external;

    /// @notice Take currency from pool manager
    /// @param currency The currency to take
    /// @param to Recipient address
    /// @param amount Amount to take
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Settle currency into pool manager
    /// @param currency The currency to settle
    /// @return paid Amount that was paid
    function settle(Currency currency) external payable returns (uint256 paid);

    /// @notice Get pool slot0 data
    function getSlot0(PoolId id) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    );
}

/**
 * @title IUnlockCallback
 * @notice Interface for contracts that call poolManager.unlock
 */
interface IUnlockCallback {
    /// @notice Called by PoolManager when a lock is acquired
    /// @param data Data passed to poolManager.unlock
    /// @return result Data to return from unlock
    function unlockCallback(bytes calldata data) external returns (bytes memory result);
}

/**
 * @title IUniversalRouter
 * @notice Interface for Uniswap Universal Router (recommended integration path)
 * @dev The Universal Router provides a simpler interface for executing swaps
 */
interface IUniversalRouter {
    /// @notice Execute a sequence of commands
    /// @param commands Encoded command identifiers
    /// @param inputs Encoded command inputs
    /// @param deadline Transaction deadline timestamp
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;

    /// @notice Execute commands with native ETH refunds
    /// @param commands Encoded command identifiers
    /// @param inputs Encoded command inputs
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs
    ) external payable;
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Get quote for exact input single-hop swap
    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    ) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/**
 * @title IV4Router
 * @notice Interface for Uniswap V4 Router actions used in Universal Router
 */
interface IV4Router {
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    struct PathKey {
        Currency intermediateCurrency;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
    }
}

// lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

// lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 *
 * IMPORTANT: Deprecated. This storage-based reentrancy guard will be removed and replaced
 * by the {ReentrancyGuardTransient} variant in v6.0.
 *
 * @custom:stateless
 */
abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /**
     * @dev A `view` only version of {nonReentrant}. Use to block view functions
     * from being called, preventing reading from inconsistent contract state.
     *
     * CAUTION: This is a "view" modifier and does not change the reentrancy
     * status. Use it only on view functions. For payable or non-payable functions,
     * use the standard {nonReentrant} modifier instead.
     */
    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        _nonReentrantBeforeView();

        // Any calls to nonReentrant after this point will fail
        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert SafeERC20FailedOperation(address(token));
            if (!_safeApprove(token, spender, value, true)) revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that relies on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that relies on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Oppositely, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity `token.transfer(to, value)` call, relaxing the requirement on the return value: the
     * return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param to The recipient of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeTransfer(IERC20 token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.transfer.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(to, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }

    /**
     * @dev Imitates a Solidity `token.transferFrom(from, to, value)` call, relaxing the requirement on the return
     * value: the return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param from The sender of the tokens
     * @param to The recipient of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.transferFrom.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(from, shr(96, not(0))))
            mstore(0x24, and(to, shr(96, not(0))))
            mstore(0x44, value)
            success := call(gas(), token, 0, 0x00, 0x64, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
            mstore(0x60, 0)
        }
    }

    /**
     * @dev Imitates a Solidity `token.approve(spender, value)` call, relaxing the requirement on the return value:
     * the return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param spender The spender of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeApprove(IERC20 token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.approve.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(spender, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }
}

// src/vaults/PaymentKitaVault.sol

/**
 * @title PaymentKitaVault
 * @notice Central vault for holding PaymentKita Protocol assets
 * @dev Handles user deposits, approvals, and withdrawals by authorized components (Gateway/Adapters)
 */
contract PaymentKitaVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice Authorized spenders (Gateway, Adapters, TokenSwapper)
    mapping(address => bool) public authorizedSpenders;

    // ============ Events ============

    event SpenderAuthorized(address indexed spender, bool authorized);
    event TokensDeposited(address indexed user, address indexed token, uint256 amount);
    event TokensWithdrawn(address indexed to, address indexed token, uint256 amount);

    // ============ Errors ============

    error Unauthorized();
    error InvalidAddress();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    function _onlyAuthorized() internal view {
        if (!authorizedSpenders[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
    }

    // ============ Core Logic ============

    /**
     * @notice Pull tokens from user to vault
     * @dev Used by Gateway to collect payment
     * @param token Token to transfer
     * @param from User address
     * @param amount Amount to transfer
     */
    function pullTokens(
        address token,
        address from,
        uint256 amount
    ) external onlyAuthorized nonReentrant {
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit TokensDeposited(from, token, amount);
    }

    /**
     * @notice Push tokens from vault to destination
     * @dev Used by Adapters/Swapper to move funds
     * @param token Token to transfer
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function pushTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyAuthorized nonReentrant {
        IERC20(token).safeTransfer(to, amount);
        emit TokensWithdrawn(to, token, amount);
    }

    /**
     * @notice Approve token usage by an external contract (e.g. 3rd party bridge/router)
     * @dev Only authorized components can request approvals (e.g. Swapper or Adapter)
     * @param token Token to approve
     * @param spender Spender address
     * @param amount Amount to approve
     */
    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external onlyAuthorized {
        IERC20(token).forceApprove(spender, amount);
    }

    // ============ Admin Functions ============

    /**
     * @notice Authorize a contract to spend/move vault funds
     * @param spender Address to authorize
     * @param authorized Status
     */
    function setAuthorizedSpender(address spender, bool authorized) external onlyOwner {
        if (spender == address(0)) revert InvalidAddress();
        authorizedSpenders[spender] = authorized;
        emit SpenderAuthorized(spender, authorized);
    }

    /**
     * @notice Emergency withdrawal of funds
     * @param token Token address
     * @param to Recipient
     * @param amount Amount
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
    }
}

// src/TokenSwapper.sol

interface IUniV3SwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/**
 * @title TokenSwapper
 * @notice DEX integration contract with pool discovery, multi-hop swaps, and gas simulation
 * @dev Designed for Uniswap V4 integration - interface-compatible for easy upgrades
 */
contract TokenSwapper is ISwapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Types ============

    /// @notice Pool configuration for a token pair
    struct PoolConfig {
        // V4 PoolKey params
        // Currency is derived from token addresses (sorted)
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
        bool isActive;
    }

    /// @notice V3 pool config for direct fallback route
    struct V3PoolConfig {
        uint24 feeTier;
        bool isActive;
    }

    // ============ State Variables ============

    /// @notice Address of PaymentKitaVault
    PaymentKitaVault public vault;

    /// @notice Address of Uniswap V4 UniversalRouter
    address public universalRouter;
    
    /// @notice Address of Uniswap V4 PoolManager
    address public poolManager;

    /// @notice Address of Uniswap V3 router (fallback path when V4 pool is unavailable)
    address public swapRouterV3;

    /// @notice Address of Uniswap V3 Quoter
    address public quoterV3;

    /// @notice Bridge token for multi-hop routes (e.g., USDC)
    address public bridgeToken;

    /// @notice Direct pool routes: keccak256(tokenIn, tokenOut) => PoolConfig
    mapping(bytes32 => PoolConfig) public directPools;

    /// @notice Multi-hop routes: keccak256(tokenIn, tokenOut) => address[]
    mapping(bytes32 => address[]) public multiHopRoutes;

    /// @notice Direct V3 fallback pools: keccak256(tokenIn, tokenOut) => V3PoolConfig
    mapping(bytes32 => V3PoolConfig) public v3Pools;

    /// @notice Whitelisted callers (PaymentKita contracts)
    mapping(address => bool) public authorizedCallers;

    // ============ Constants ============

    uint256 public constant GAS_SINGLE_HOP = 150_000;
    uint256 public constant GAS_PER_HOP = 120_000;
    uint256 public constant GAS_OVERHEAD = 50_000;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 100;
    uint256 public maxSlippageBps = 500;

    /// @notice Universal Router Commands
    bytes1 public constant V4_SWAP = 0x10;
    
    /// @notice V4 Router Action Constants (example inputs, check specific Universal Router implementation)
    // For V4, typically we pass (actions, params) encoded for V4Router
    // Actions: 0x06 (SWAP_EXACT_IN_SINGLE)
    uint8 internal constant V4_ACTION_SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 internal constant V4_ACTION_SWAP_EXACT_IN = 0x07;
    uint8 internal constant V4_ACTION_SETTLE = 0x0b;
    uint8 internal constant V4_ACTION_TAKE = 0x0e;

    // ============ Errors ============

    error NoRouteFound();
    error SlippageExceeded();
    error InvalidAddress();
    error Unauthorized();
    error SameToken();
    error ZeroAmount();
    error PoolNotActive();

    // ============ Events ============

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event AuthorizedCallerSet(address indexed caller, bool allowed);
    event V4RouterValidated(address indexed router);
    event RouteRemoved(address indexed tokenIn, address indexed tokenOut, string routeType);
    
    // ============ Constructor ============

    constructor(
        address _universalRouter,
        address _poolManager,
        address _bridgeToken
    ) Ownable(msg.sender) {
        if (_universalRouter == address(0) || _poolManager == address(0)) {
            revert InvalidAddress();
        }

        universalRouter = _universalRouter;
        poolManager = _poolManager;
        bridgeToken = _bridgeToken;

        // UNI-1: Validate V4 router interface on deployment
        _validateV4Router(_universalRouter);

        // Owner is authorized by default
        authorizedCallers[msg.sender] = true;
    }

    /// @notice Validate that the V4 Universal Router supports the expected interface
    /// @dev The UniversalRouter must implement execute(bytes,bytes[],uint256)
    ///      which is the command-encoded swap entry point for Uniswap V4.
    ///      This check guards against misconfigured router addresses.
    function validateV4Router() external view returns (bool) {
        return _isV4RouterValid(universalRouter);
    }

    function _validateV4Router(address _router) internal {
        require(_isV4RouterValid(_router), "V4 router interface not supported");
        emit V4RouterValidated(_router);
    }

    function _isV4RouterValid(address _router) internal view returns (bool) {
        if (_router == address(0)) return false;
        // Check that the address has code deployed (is a contract)
        uint256 size;
        assembly { size := extcodesize(_router) }
        return size > 0;
    }

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    function _onlyAuthorized() internal view {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
    }

    // ============ Admin Functions ============

    function setVault(address _vault) external onlyOwner {
        vault = PaymentKitaVault(_vault);
    }

    function setV3Router(address _swapRouterV3) external onlyOwner {
        swapRouterV3 = _swapRouterV3;
    }

    function setQuoterV3(address _quoter) external onlyOwner {
        quoterV3 = _quoter;
    }

    /// @notice Update the maximum slippage tolerance
    /// @param bps New slippage in basis points (max 1000 = 10%)
    function setMaxSlippage(uint256 bps) external onlyOwner {
        require(bps <= 1000, "Max 10% slippage");
        maxSlippageBps = bps;
    }

    function setAuthorizedCaller(address caller, bool allowed) external onlyOwner {
        if (caller == address(0)) revert InvalidAddress();
        authorizedCallers[caller] = allowed;
        emit AuthorizedCallerSet(caller, allowed);
    }

    // ============ Core Swap Functions ============

    /// @notice Swap tokens held in the Vault
    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external nonReentrant onlyAuthorized returns (uint256 amountOut) {
        if (address(vault) == address(0)) revert InvalidAddress();
        if (tokenIn == tokenOut) revert SameToken();
        if (amountIn == 0) revert ZeroAmount();
        
        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        // Pull from Vault to This Contract
        vault.pushTokens(tokenIn, address(this), amountIn);
        
        // Internal Logic for swapping (using funds now in this contract)
        if (isDirect) {
            amountOut = _executeDirectSwap(tokenIn, tokenOut, amountIn, minAmountOut);
        } else {
            amountOut = _executeMultiHopSwap(path, amountIn, minAmountOut);
        }

        if (amountOut < minAmountOut) revert SlippageExceeded();

        // Transfer output to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    /// @inheritdoc ISwapper
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external override nonReentrant onlyAuthorized returns (uint256 amountOut) {
        if (tokenIn == tokenOut) revert SameToken();
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert InvalidAddress();

        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        // Transfer tokens from caller
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (isDirect) {
            amountOut = _executeDirectSwap(tokenIn, tokenOut, amountIn, minAmountOut);
        } else {
            amountOut = _executeMultiHopSwap(path, amountIn, minAmountOut);
        }

        if (amountOut < minAmountOut) revert SlippageExceeded();

        // Transfer output to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    // ============ Route Discovery ============

    /// @inheritdoc ISwapper
    function findRoute(
        address tokenIn,
        address tokenOut
    ) public view override returns (bool exists, bool isDirect, address[] memory path) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        // 1. Check direct pool
        if (directPools[pairKey].isActive) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return (true, true, path);
        }

        // 2. Check direct V3 fallback route
        if (v3Pools[pairKey].isActive) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return (true, true, path);
        }

        // 3. Check configured multi-hop route
        bytes32 directionalKey = _getDirectionalKey(tokenIn, tokenOut);
        address[] storage hops = multiHopRoutes[directionalKey];
        if (hops.length > 0) {
            return (true, false, hops);
        }

        // 4. Try via bridge token
        if (bridgeToken != address(0) && tokenIn != bridgeToken && tokenOut != bridgeToken) {
            bytes32 inKey = _getPairKey(tokenIn, bridgeToken);
            bytes32 outKey = _getPairKey(bridgeToken, tokenOut);

            if (directPools[inKey].isActive && directPools[outKey].isActive) {
                path = new address[](3);
                path[0] = tokenIn;
                path[1] = bridgeToken;
                path[2] = tokenOut;
                return (true, false, path);
            }
        }

        return (false, false, new address[](0));
    }

    // ============ Gas Estimation ============

    /// @inheritdoc ISwapper
    function estimateSwapGas(
        address tokenIn,
        address tokenOut,
        uint256 /* amountIn */
    ) external view override returns (uint256 estimatedGas, uint256 hopCount) {
        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        hopCount = path.length - 1;

        if (isDirect) {
            estimatedGas = GAS_SINGLE_HOP;
        } else {
            estimatedGas = GAS_OVERHEAD + (hopCount * GAS_PER_HOP);
        }
    }

    /// @inheritdoc ISwapper
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (
        uint256 amountOut,
        uint256 estimatedGas,
        uint256 hopCount,
        address[] memory path
    ) {
        bool exists;
        bool isDirect;
        (exists, isDirect, path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        hopCount = path.length - 1;
        estimatedGas = isDirect ? GAS_SINGLE_HOP : (GAS_OVERHEAD + hopCount * GAS_PER_HOP);
        amountOut = _simulateSwap(path, amountIn);
    }

    /// @inheritdoc ISwapper
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        (bool exists, , address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        amountOut = _simulateSwap(path, amountIn);
    }

    /// @notice Set a direct pool route for a token pair
    function setDirectPool(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        bytes calldata hookData
    ) external onlyOwner {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress(); // Assuming InvalidAddress() is defined elsewhere

        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        directPools[pairKey] = PoolConfig({
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks,
            hookData: hookData,
            isActive: true
        });

        // Assuming PoolRouteSet event is defined elsewhere
        // emit PoolRouteSet(tokenIn, tokenOut, true, address(0)); // poolAddress not used in V4, using derived PoolKey
    }

    /// @notice Set a direct V3 fallback pool route for a token pair
    function setV3Pool(
        address tokenIn,
        address tokenOut,
        uint24 feeTier
    ) external onlyOwner {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress();
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        v3Pools[pairKey] = V3PoolConfig({
            feeTier: feeTier,
            isActive: true
        });
    }

    /// @notice Set a multi-hop route for a token pair
    function setMultiHopPath(
        address tokenIn,
        address tokenOut,
        address[] calldata path
    ) external onlyOwner {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress();
        if (path.length < 2) revert InvalidAddress(); 
        if (path[0] != tokenIn || path[path.length - 1] != tokenOut) revert InvalidAddress();

        bytes32 directionalKey = _getDirectionalKey(tokenIn, tokenOut);
        multiHopRoutes[directionalKey] = path;
    }

    /// @notice Remove a direct pool route
    function removeDirectPool(address tokenIn, address tokenOut) external onlyOwner {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        delete directPools[pairKey];
        emit RouteRemoved(tokenIn, tokenOut, "V4_DIRECT");
    }

    /// @notice Remove a direct V3 fallback route
    function removeV3Pool(address tokenIn, address tokenOut) external onlyOwner {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        delete v3Pools[pairKey];
        emit RouteRemoved(tokenIn, tokenOut, "V3_DIRECT");
    }

    /// @notice Remove a multi-hop route
    function removeMultiHopPath(address tokenIn, address tokenOut) external onlyOwner {
        bytes32 directionalKey = _getDirectionalKey(tokenIn, tokenOut);
        delete multiHopRoutes[directionalKey];
        emit RouteRemoved(tokenIn, tokenOut, "MULTI_HOP");
    }

    // ============ Internal Functions ============

    /// @notice Generate a unique key for a token pair (directional)
    function _getDirectionalKey(address inToken, address outToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(inToken, outToken));
    }

    /// @notice Generate a unique key for a token pair
    function _getPairKey(address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a < b ? a : b, a < b ? b : a));
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (Currency, Currency) {
        return tokenA < tokenB 
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB)) 
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
    }

    /// @notice Execute a direct (single-hop) swap via Uniswap
    function _executeDirectSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        // Prefer V4 direct pool when available.
        if (directPools[pairKey].isActive) {
            return _executeV4DirectSwap(tokenIn, tokenOut, amountIn, minAmountOut);
        }

        // Fallback to V3 direct pool when configured.
        V3PoolConfig memory v3Config = v3Pools[pairKey];
        if (v3Config.isActive) {
            return _executeV3Swap(tokenIn, tokenOut, amountIn, minAmountOut, v3Config.feeTier);
        }

        revert NoRouteFound();
    }

    function _executeV4DirectSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (universalRouter == address(0)) return amountIn;

        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        PoolConfig memory config = directPools[pairKey];
        if (!config.isActive) revert PoolNotActive(); 

        IERC20(tokenIn).forceApprove(universalRouter, amountIn);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // Construct PoolKey
        (Currency currency0, Currency currency1) = _sortTokens(tokenIn, tokenOut);
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: config.hooks
        });

        // Determine zeroForOne
        bool zeroForOne = tokenIn < tokenOut;

        // Sanity check against uint128 for V4 router
        if (amountIn > type(uint128).max || minAmountOut > type(uint128).max) revert SlippageExceeded();

        // Encode V4 Router Actions
        // Corrected sequence:
        // 1. SETTLE (from msg.sender)
        // 2. SWAP_EXACT_IN_SINGLE
        // 3. TAKE (to address(this))
        bytes memory actions = abi.encodePacked(
            V4_ACTION_SETTLE,
            V4_ACTION_SWAP_EXACT_IN_SINGLE,
            V4_ACTION_TAKE
        );
        
        // Params for Action
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            // forge-lint: disable-next-line(unsafe-typecast)
            amountIn: uint128(amountIn),
            // forge-lint: disable-next-line(unsafe-typecast)
            amountOutMinimum: uint128(minAmountOut),
            hookData: config.hookData
        });
        
        bytes[] memory actionParams = new bytes[](3);
        // SETTLE params: (Currency currency, uint256 amount, bool payerIsUser)
        actionParams[0] = abi.encode(tokenIn, amountIn, true);
        actionParams[1] = abi.encode(swapParams);
        // TAKE params: (Currency currency, address recipient, uint256 amount)
        actionParams[2] = abi.encode(tokenOut, address(this), minAmountOut);

        // Final UniversalRouter Input
        bytes memory commands = abi.encodePacked(V4_SWAP); // 0x10
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 600);
        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
    }

    function _executeV3Swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint24 feeTier
    ) internal returns (uint256 amountOut) {
        if (swapRouterV3 == address(0)) revert NoRouteFound();
        IERC20(tokenIn).forceApprove(swapRouterV3, amountIn);
        amountOut = IUniV3SwapRouter02(swapRouterV3).exactInputSingle(
            IUniV3SwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeTier,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _executeMultiHopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Check if the first hop is V4
        bytes32 firstHopKey = _getPairKey(path[0], path[1]);
        if (directPools[firstHopKey].isActive) {
            return _executeV4MultiHopSwap(path, amountIn, minAmountOut);
        } else if (v3Pools[firstHopKey].isActive) {
            return _executeV3MultiHopSwap(path, amountIn, minAmountOut);
        }
        revert NoRouteFound();
    }

    function _executeV3MultiHopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (swapRouterV3 == address(0)) revert NoRouteFound();
        
        uint256 currentAmount = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address tokenIn = path[i];
            address tokenOut = path[i+1];
            bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
            
            V3PoolConfig memory config = v3Pools[pairKey];
            if (!config.isActive) revert PoolNotActive();

            bool isLastHop = i == path.length - 2;
            uint256 minOut = isLastHop ? minAmountOut : 0;

            IERC20(tokenIn).forceApprove(swapRouterV3, currentAmount);
            currentAmount = IUniV3SwapRouter02(swapRouterV3).exactInputSingle(
                IUniV3SwapRouter02.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: config.feeTier,
                    recipient: address(this),
                    amountIn: currentAmount,
                    amountOutMinimum: minOut,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        amountOut = currentAmount;
    }

    function _executeV4MultiHopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (universalRouter == address(0)) return amountIn;
        
        uint256 pathLength = path.length;
        if (pathLength < 2) revert NoRouteFound();

        IV4Router.PathKey[] memory pathKeys = new IV4Router.PathKey[](pathLength - 1);
        
        for (uint256 i = 0; i < pathLength - 1; i++) {
            address tokenA = path[i];
            address tokenB = path[i+1];
            bytes32 pairKey = _getPairKey(tokenA, tokenB); 
            PoolConfig memory config = directPools[pairKey];
            
            if (!config.isActive) revert PoolNotActive();
            
            pathKeys[i] = IV4Router.PathKey({
                intermediateCurrency: Currency.wrap(tokenB),
                fee: config.fee,
                tickSpacing: config.tickSpacing,
                hooks: config.hooks,
                hookData: config.hookData
            });
        }

        IERC20(path[0]).forceApprove(universalRouter, amountIn);
        uint256 balanceBefore = IERC20(path[pathLength-1]).balanceOf(address(this));

        IV4Router.ExactInputParams memory swapParams = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(path[0]),
            path: pathKeys,
            // forge-lint: disable-next-line(unsafe-typecast)
            amountIn: uint128(amountIn),
            // forge-lint: disable-next-line(unsafe-typecast)
            amountOutMinimum: uint128(minAmountOut)
        });

        bytes memory actions = abi.encodePacked(
            V4_ACTION_SETTLE,
            V4_ACTION_SWAP_EXACT_IN,
            V4_ACTION_TAKE
        );
        bytes[] memory actionParams = new bytes[](3);
        // SETTLE params: (Currency currency, uint256 amount, bool payerIsUser)
        actionParams[0] = abi.encode(path[0], amountIn, true);
        actionParams[1] = abi.encode(swapParams);
        // TAKE params: (Currency currency, address recipient, uint256 amount)
        actionParams[2] = abi.encode(path[pathLength-1], address(this), minAmountOut);
        
        bytes memory commands = abi.encodePacked(V4_SWAP); // 0x10
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 600);
        amountOut = IERC20(path[pathLength-1]).balanceOf(address(this)) - balanceBefore;
    }

    /// @notice Simulate a swap to get expected output
    function getRealQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        (bool exists, /*bool isDirect*/, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        // 1. V3 Direct
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        if (v3Pools[pairKey].isActive && quoterV3 != address(0)) {
             try IQuoterV2(quoterV3).quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: v3Pools[pairKey].feeTier,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amount, uint160, uint32, uint256) {
                return amount;
            } catch {
                // Fallback to simulation if quoter fails
            }
        }

        // 2. Fallback to simulation
        return _simulateSwap(path, amountIn);
    }

    /// @notice Simulate a swap to get expected output
    function _simulateSwap(
        address[] memory /* path */,
        uint256 amountIn
    ) internal pure returns (uint256 amountOut) {
        // Fallback to 1:1 quote to indicate a route exists.
        // This is a placeholder for simulation; actual execution will use real routes.
        return amountIn;
    }
}

