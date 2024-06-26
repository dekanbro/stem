// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IFinalizationStrategy.sol";
import "./interfaces/IVotes.sol";
import "./interfaces/IPoints.sol";
import "./interfaces/IChoices.sol";
import "./interfaces/IContest.sol";

contract Contest is IContest {
    IVotes public votesContract;
    IPoints public pointsContract;
    IChoices public choicesContract;
    IFinalizationStrategy public finalizationStrategy;

    uint256 public startTime;
    uint256 public endTime;
    bool public isFinalized;

    mapping(bytes32 => uint256) public choicesIdx;
    bytes32[] public choiceList;

    event ContestStarted(uint256 startTime, uint256 endTime);
    event ContestFinalized(bytes32[] winningChoices);

    constructor(
        IVotes _votesContract,
        IPoints _pointsContract,
        IChoices _choicesContract,
        IFinalizationStrategy _finalizationStrategy,
        uint256 _startTime,
        uint256 _duration
    ) {
        require(
            _startTime >= block.timestamp,
            "Start time must be in the future"
        );
        votesContract = _votesContract;
        pointsContract = _pointsContract;
        choicesContract = _choicesContract;
        finalizationStrategy = _finalizationStrategy;

        startTime = _startTime;
        endTime = _startTime + _duration;
    }

    modifier onlyDuringVotingPeriod() {
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "Voting is not active"
        );
        _;
    }

    modifier onlyAfterEnd() {
        require(block.timestamp > endTime, "Contest is still active");
        _;
    }

    function claimPoints() virtual public onlyDuringVotingPeriod {
        pointsContract.claimPoints();
    }

    function vote(
        bytes32 choiceId,
        uint256 amount
    ) virtual public onlyDuringVotingPeriod {
        pointsContract.allocatePoints(msg.sender, amount);
        votesContract.vote(choiceId, amount);

        // Add choice to list if not already present
        if (choicesIdx[choiceId] == 0) {
            choiceList.push(choiceId);
            choicesIdx[choiceId] = choiceList.length;
        }
    }

    function retractVote(
        bytes32 choiceId,
        uint256 amount
    ) virtual public onlyDuringVotingPeriod {
        pointsContract.releasePoints(msg.sender, amount);
        votesContract.retractVote(choiceId, amount);
    }

    function changeVote(
        bytes32 oldChoiceId,
        bytes32 newChoiceId,
        uint256 amount
    ) virtual public onlyDuringVotingPeriod {
        retractVote(oldChoiceId, amount);
        vote(newChoiceId, amount);
    }

    function finalize() virtual public onlyAfterEnd {
        bytes32[] memory winningChoices = finalizationStrategy.finalize(
            address(this),
            choiceList
        );

        // loop through winning choicesIdx and execute
        for (uint256 i = 0; i < winningChoices.length; i++) {
            executeChoice(winningChoices[i]);
        }
        isFinalized = true;
        emit ContestFinalized(winningChoices);
    }

    function executeChoice(bytes32 choice) virtual internal {
        (, bytes memory data) = choicesContract.getChoice(choice);
        require(data.length > 0, "No executable data found");

        // Perform the delegatecall
        (bool success, ) = address(this).delegatecall(data);
        require(success, "Execution failed");
    }

    // getters

    function getTotalVotesForChoice(
        bytes32 choiceId
    ) public view override returns (uint256) {
        return votesContract.getTotalVotesForChoice(choiceId);
    }

    function getChoices() external view override returns (bytes32[] memory) {
        return choiceList;
    }
}
