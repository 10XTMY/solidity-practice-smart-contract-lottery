// SPDX-License-Identifier: MIT

// Layout of Contract:
// pragma statements
// imports
// events
// errors
// interfaces
// libraries
// contracts

// inside each contract, library, or interface:
// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

/**
 * @title Raffle
 * @author 10XTMY
 * @notice A raffle contract
 * @dev Implements Chainlink VRFv2
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {console} from "forge-std/Test.sol";

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent(); // name errorsafter contract
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );
    enum RaffleState {
        OPEN,
        CALCULATING_WINNER,
        CLOSED
    }
    RaffleState private s_raffleState;
    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;

    // @dev Chainlink VRF
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    // Events are cheaper than errors
    // indexed parameters are called Topics (array of 32 bytes, order dependent)
    // non indexed are harder to search through because you need the abi to find them
    // non indexed costs less gas, if you don't need to search through them
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    // event Raffle__WinnerPicked(address indexed winner, uint256 indexed amount);

    // emit to trigger events
    // emit Raffle__WinnerPicked(winner, amount);

    // VRF Subscription ID 6773

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        // custom errors are more gas efficient than require statements
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the func that the Chainlink Automation nodes call
     * to see if it is time to perform an upkeep.
     * The following should be tru for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH / players
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpKeep(
        bytes memory /* checkData */
    ) public view returns (bool upKeepNeeded, bytes memory /* performData */) {
        // check if enough time has passed
        // bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        // check if raffle is open
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        // check if there is enough ETH and players
        bool enoughEth = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = (timeHasPassed &&
            raffleIsOpen &&
            enoughEth &&
            hasPlayers);
        return (upKeepNeeded, "0x0");
    }

    // pick winner
    // be automatically called using chainlink automation
    // function pickWinner() external {
    function performUpkeep(bytes calldata /* performData */) external {
        // checks
        (bool upKeepNeeded, ) = checkUpKeep("");
        console.log("upKeepNeeded: %s", upKeepNeeded);
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING_WINNER;
        // get random number from chainlink VRF
        // this is a two transaction function
        // 1. Request RNG ->
        // 2. Receive RNG <-
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            // coordinator address different chain to chain
            // so we set it up in the constructor
            i_gasLane, // gas lane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit, // limit cost on second transaction
            NUM_WORDS
        );
        // Below is for testing
        // Emitting this is redundant because the VRF Coordinator emits it already
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // checks <- do checks first to avoid wasting gas,
        // also protects against reentrancy attacks
        // effects
        // events
        // interactions

        // using modulo to get random index
        // s_players = 10
        // rng = 12
        // 12 % 10 = 2 <- winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;

        emit PickedWinner(winner);

        // transfer balance to winner
        (bool successs, ) = winner.call{value: address(this).balance}("");
        if (!successs) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayerAtIndex(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
