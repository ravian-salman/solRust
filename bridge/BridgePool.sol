// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <=0.8.0;

import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../common/SafeAmount.sol";
import "../token/TaxDistributor.sol";

contract BridgePool is EIP712, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    event TransferBySignature(bytes32 hash, address signer, address receiver, address token, uint256 amount);
    event BridgeLiquidityAdded(address actor, address token, uint256 amount);
    event BridgeLiquidityRemoved(address actor, address token, uint256 amount);
    event BridgeSwap(address from,
        address indexed token,
        uint256 targetNetwork,
        address targetToken,
        address targetAddrdess,
        uint256 amount,
        uint256 fee);

    string constant NAME = "FERRUM_TOKEN_BRIDGE_POOL";
    string constant VERSION = "000.001";
    address public signer;
    mapping(bytes32=>bool) public usedHashes;
    mapping(address=>mapping(address=>uint256)) private liquidities;
    mapping(address=>uint256) public fees;
    address public feeDistributor;

    constructor () EIP712(NAME, VERSION) { }

    function setSigner(address _signer) external onlyOwner() {
        require(_signer != address(0), "Bad signer");
        signer = _signer;
    }

    function setFee(address token, uint256 fee10000) external onlyOwner() {
        require(token != address(0), "Bad token");
        fees[token] = fee10000;
    }

    function setFeeDistributor(address _feeDistributor) external onlyOwner() {
        feeDistributor = _feeDistributor;
    }

    function _swap(address from, address token, uint256 amount, uint256 targetNetwork,
        address targetToken, address targetAddress) internal returns(uint256) {
        uint256 actualAmount = amount;
        uint256 fee = 0;
        address _feeDistributor = feeDistributor;
        if (_feeDistributor != address(0)) {
            fee = amount.mul(fees[token]).div(10000);
            actualAmount = amount.sub(fee);
            if (fee != 0) {
                IERC20(token).transferFrom(from, _feeDistributor, fee);
            }
        }
        IERC20(token).transferFrom(from, address(this), actualAmount);
        emit BridgeSwap(from, token, targetNetwork, targetToken, targetAddress, actualAmount, fee);
        return actualAmount;
    }

    function swap(address token, uint256 amount, uint256 targetNetwork, address targetToken) external returns(uint256) {
        return _swap(msg.sender, token, amount, targetNetwork, targetToken, address(0));
    }

    function swapToAddress(address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken,
        address targetAddress) external returns(uint256) {
        require(targetAddress != address(0), "BridgePool: targetAddress is required");
        return _swap(msg.sender, token, amount, targetNetwork, targetToken, targetAddress);
    }

    function withdrawSigned(
            address token,
            address payee,
            uint256 amount,
            bytes32 salt,
            bytes calldata signature) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
          keccak256("WithdrawSigned(address token, address payee,uint256 amount,bytes32 salt)"),
          token,
          payee,
          amount,
          salt
        )));
        require(!usedHashes[digest], "Message already used");
        address _signer = ECDSA.recover(digest, signature);
        require(_signer == signer, "BridgePool: Invalid signer");
        usedHashes[digest] = true;
        IERC20(token).safeTransfer(payee, amount);
        emit TransferBySignature(digest, _signer, payee, token, amount);
    }

    function addLiquidity(address token, uint256 amount) public {
        require(amount != 0, "Amount must be positive");
        require(token != address(0), "Bad token");
        amount = SafeAmount.safeTransferFrom(token, msg.sender, address(this), amount);
        liquidities[token][msg.sender] = liquidities[token][msg.sender].add(amount);
        emit BridgeLiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidityIfPossible(address token, uint256 amount) public returns (uint256) {
        require(amount != 0, "Amount must be positive");
        require(token != address(0), "Bad token");
        uint256 liq = liquidities[token][msg.sender];
        require(liq >= amount, "Not enough liquidity");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 actualLiq = balance > amount ? amount : balance;
        liquidities[token][msg.sender] = liquidities[token][msg.sender].sub(actualLiq);
        if (actualLiq != 0) {
            IERC20(token).safeTransfer(msg.sender, actualLiq);
            emit BridgeLiquidityRemoved(msg.sender, token, amount);
        }
        return actualLiq;
    }

    function liquidity(address token, address liquidityAdder) public view returns (uint256) {
        return liquidities[token][liquidityAdder];
    }
}