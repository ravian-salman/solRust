// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <=0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../staking/RewardDistributor.sol";

interface IERC20Burnable {
    function burn(uint256 amount) external;
}

interface ITaxDistributor {
    function distributeTax(address token) external returns(bool);
}

contract TaxDistributor is ITaxDistributor, Ownable {
    using SafeMath for uint256;
    struct Distribution {
        uint8 stake;
        uint8 burn;
        uint8 future;
        uint8 dev;
    }

    mapping(address => Distribution) distribution;
    mapping(address => IRewardDistributor) rewardDistributor;
    mapping(address => address) devAddress;
    mapping(address => address) futureAddress;
    address globalDevAddress;
    uint256 globalDevFeePer100;

    function setRewardDistributor(address token, address _rewardDistributor)
    onlyOwner()
    external returns(bool) {
        require(address(token) != address(0), "TaxDistributor: Bad token");
        IRewardDistributor rd = IRewardDistributor(_rewardDistributor);
        address someAddress = rd.rollAndGetDistributionAddress(msg.sender);
        require(someAddress != address(0), "TaxDistributor: Bad reward distributor");
        rewardDistributor[token] = rd;
        return true;
    }

    function setDevAddress(address token, address _devAddress)
    onlyOwner()
    external returns(bool) {
        require(address(token) != address(0), "TaxDistributor: Bad token");
        devAddress[token] = _devAddress; // Allow 0
        return true;
    }

    function setGlobalDevAddress(address _devAddress, uint256 devFeePer100)
    onlyOwner()
    external returns(bool) {
        require(devFeePer100 < 100, "TaxDistributor: Invalid devFeePer100");
        globalDevAddress = _devAddress; // Allow 0
        globalDevFeePer100 = devFeePer100;
        return true;
    }

    function setFutureAddress(address token, address _futureAddress)
    onlyOwner()
    external returns(bool) {
        require(address(token) != address(0), "TaxDistributor: Bad token");
        futureAddress[token] = _futureAddress; // Allow 0
        return true;
    }

    function setDefaultDistribution(address token, uint8 stake, uint8 burn, uint8 dev, uint8 future)
    onlyOwner()
    external returns(bool) {
        require(address(token) != address(0), "TaxDistributor: Bad token");
        require(stake+burn+dev+future == 100, "StakeDevBurnTaxable: taxes must add to 100");
        distribution[token] = Distribution({ stake: stake, burn: burn, dev: dev, future: future });
    }

    /**
     * @dev Can be called by anybody, but make this contract is tax exempt.
     */
    function distributeTax(address token) external override returns(bool) {
        return _distributeTax(token, IERC20(token).balanceOf(address(this)));
    }

    function _distributeTax(address token, uint256 amount) internal returns(bool) {
        Distribution memory dist = distribution[token];
        uint256 remaining = amount;
        uint256 _globalDevFeePer100 = globalDevFeePer100;
        if (_globalDevFeePer100 != 0) {
            uint256 globalDevAmount = amount.mul(_globalDevFeePer100).div(100);
            if (globalDevAmount != 0) {
                IERC20(token).transfer(globalDevAddress, globalDevAmount);
                remaining = remaining.sub(globalDevAmount);
            }
        }
        if (dist.burn != 0) {
            uint256 burnAmount = amount.mul(dist.burn).div(100);
            if (burnAmount != 0) {
                IERC20Burnable(token).burn(burnAmount);
                remaining = remaining.sub(burnAmount);
            }
        }
        if (dist.dev != 0) {
            uint256 devAmount = amount.mul(dist.dev).div(100);
            if (devAmount != 0) {
                IERC20(token).transfer(devAddress[token], devAmount);
                remaining = remaining.sub(devAmount);
            }
        }
        if (dist.future != 0) {
            uint256 futureAmount = amount.mul(dist.future).div(100);
            if (futureAmount != 0) {
                IERC20(token).transfer(futureAddress[token], futureAmount);
                remaining = remaining.sub(futureAmount);
            }
        }
        if (dist.stake != 0) {
            uint256 stakeAmount = remaining;
            address stakeAddress = rewardDistributor[token].rollAndGetDistributionAddress(msg.sender);
            if (stakeAddress != address(0)) {
                IERC20(token).transfer(stakeAddress, stakeAmount);
                bool res = rewardDistributor[token].updateRewards(stakeAddress);
                require(res, "StakeDevBurnTaxable: Error staking rewards");
            }
        }
        return true;
    }
}