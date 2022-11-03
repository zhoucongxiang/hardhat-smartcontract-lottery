// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

error Raffle2__NotEnoughETHEntered();
error Raffle2__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
error Raffle2__TransferFailed();

contract Raffle2 is AutomationCompatibleInterface, VRFConsumerBaseV2 {
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // local variable
    uint256 private immutable i_entranceFee;
    address[] private s_players;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;
    address private s_recentWinner;
    // mapping(address => uint256) private s_addressToAmountFunded;

    // VRF variable
    VRFCoordinatorV2Interface private immutable i_coordinator;
    bytes32 private immutable i_keyHash;
    uint64 private immutable s_subscriptionId;
    uint16 private constant REQUESTCONFIRMATIONS = 3;
    uint32 private constant CALLBACKGASLIMIT = 100000;
    uint32 private constant NUMWORDS = 1;
    uint256 private s_randomWords;

    //Events
    event RaffleEnter(address indexed player, uint256 indexed actualEntranceFee);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address player, uint256 randomWords);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address coordinator,
        bytes32 keyHash,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(coordinator) {
        i_entranceFee = entranceFee;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;

        i_coordinator = VRFCoordinatorV2Interface(coordinator);
        i_keyHash = keyHash;
        s_subscriptionId = subscriptionId;
    }

    // 1. 入场
    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle2__NotEnoughETHEntered();
        }

        s_players.push(msg.sender);

        emit RaffleEnter(msg.sender, msg.value);
    }

    // 2. 自动调度
    // 3. Request VRF
    // 4. 中奖逻辑
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
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = (address(this).balance > 0);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayer = (s_players.length > 0);

        upkeepNeeded = (isOpen && hasBalance && timePassed && hasPlayer);
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle2__UpkeepNotNeeded(
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
        s_recentWinner = s_players[s_randomWords % s_players.length];

        s_players = new address[](0);

        (bool success, ) = payable(s_recentWinner).call{value: address(this).balance}("");

        if (!success) {
            revert Raffle2__TransferFailed();
        }

        emit WinnerPicked(s_recentWinner, s_randomWords);
    }
}
