// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__RaffleNotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/**@title A sample Raffle Contract
 * @author zcx
 * @notice This contract is for creating a sample raffle contract
 * @dev This implements the Chainlink VRF Version 2
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    // Type declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // Lottery Variables
    uint256 private immutable i_entranceFee;
    address[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;

    // Chainlink VRF veriables
    VRFCoordinatorV2Interface private immutable i_coordinator;
    bytes32 private immutable i_keyHash;
    uint64 private immutable s_subscriptionId;
    uint16 private constant REQUESTCONFIRMATIONS = 3;
    uint32 private constant CALLBACKGASLIMIT = 100000;
    uint32 private constant NUMWORDS = 1;
    uint256 private s_randomWords;

    // Events
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    constructor(
        address coordinator,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint256 entranceFee,
        uint256 interval
    ) VRFConsumerBaseV2(coordinator) {
        i_entranceFee = entranceFee;

        i_coordinator = VRFCoordinatorV2Interface(coordinator);
        i_keyHash = keyHash;
        s_subscriptionId = subscriptionId;

        s_raffleState = RaffleState.OPEN;

        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHEntered();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(msg.sender);

        emit RaffleEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        // return (upkeepNeeded, "0x0"); // can we comment this out?
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_coordinator.requestRandomWords(
            i_keyHash,
            s_subscriptionId,
            REQUESTCONFIRMATIONS,
            CALLBACKGASLIMIT,
            NUMWORDS
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256, /*_requestId */
        uint256[] memory _randomWords
    ) internal override {
        s_randomWords = _randomWords[0];
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        s_recentWinner = s_players[indexOfWinner];

        s_players = new address[](0);

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;

        (bool success, ) = payable(s_recentWinner).call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(s_recentWinner);
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getRandomWord() public view returns (uint256) {
        return s_randomWords;
    }
}
