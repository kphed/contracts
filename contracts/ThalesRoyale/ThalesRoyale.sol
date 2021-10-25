pragma solidity ^0.5.16;

import "synthetix-2.50.4-ovm/contracts/Pausable.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "synthetix-2.50.4-ovm/contracts/SafeDecimalMath.sol";
import "../interfaces/IPriceFeed.sol";

contract ThalesRoyale is Owned, Pausable {
    using SafeMath for uint;
    using SafeDecimalMath for uint;
    using SafeERC20 for IERC20;

    uint public reward;
    IERC20 public rewardToken;
    bytes32 public oracleKey;
    IPriceFeed public priceFeed;
    uint public rounds;
    uint public maxParticipants;
    uint public signUpPeriod = 24 hours;

    address[] public players;
    mapping(address => uint) public playerSignedUp;

    uint public creationTime;

    constructor(
        address _owner,
        bytes32 oracleKey,
        IPriceFeed priceFeed,
        uint reward,
        address rewardToken,
        uint rounds,
        uint maxParticipants
    ) public Owned(_owner) {
        creationTime = block.timestamp;
    }

    function signUp() external {
        require(block.timestamp < creationTime + signUpPeriod, "Sign up period has expired");
        require(playerSignedUp[msg.sender] == 0, "Player already signed up");
        playerSignedUp[msg.sender] = block.timestamp;
        players.push(msg.sender);
    }
}