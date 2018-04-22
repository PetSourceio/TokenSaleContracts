pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "./Crowdsale.sol";
import "./Token.sol";

contract TeamTokenHolder is Ownable {
  using SafeMath for uint256;

  uint256 private LOCKUP_TIME = 24; // in months

  Crowdsale crowdsale;
  Token token;
  uint256 public collectedTokens;

  function TeamTokenHolder(address _owner, address _crowdsale, address _token) public {
    owner = _owner;
    crowdsale = Crowdsale(_crowdsale);
    token = Token(_token);
  }

  /*
    @notice The Dev (Owner) will call this method to extract the tokens
  */
  function collectTokens() public onlyOwner {
    uint256 balance = token.balanceOf(address(this));
    uint256 total = collectedTokens.add(balance);

    uint256 finalizedTime = crowdsale.finalizedTime();

    require(finalizedTime > 0 && getTime() >= finalizedTime.add(months(3)));

    uint256 canExtract = total.mul(getTime().sub(finalizedTime)).div(months(LOCKUP_TIME));

    canExtract = canExtract.sub(collectedTokens);

    if (canExtract > balance) {
      canExtract = balance;
    }

    collectedTokens = collectedTokens.add(canExtract);
    assert(token.transfer(owner, canExtract));

    TokensWithdrawn(owner, canExtract);
  }

  function months(uint256 m) internal pure returns (uint256) {
      return m.mul(30 days);
  }

  function getTime() internal view returns (uint256) {
    return now;
  }

  /*
     Safety Methods
  */

  /*
     @notice This method can be used by the controller to extract mistakenly
     sent tokens to this contract.
     @param _token The address of the token contract that you want to recover
     set to 0 in case you want to extract ether.
  */
  function claimTokens(address _token) public onlyOwner {
    require(_token != address(token));
    if (_token == 0x0) {
      owner.transfer(this.balance);
      return;
    }

    Token _Token = Token(_token);
    uint256 balance = _Token.balanceOf(this);
    _Token.transfer(owner, balance);
    ClaimedTokens(_token, owner, balance);
  }

  event ClaimedTokens(address indexed _token, address indexed _controller, uint256 _amount);
  event TokensWithdrawn(address indexed _holder, uint256 _amount);
}
