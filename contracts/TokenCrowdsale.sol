pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/crowdsale/validation/WhitelistedCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/price/IncreasingPriceCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/emission/MintedCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/distribution/FinalizableCrowdsale.sol";
import './Token.sol';

contract TokenCrowdsale is MintedCrowdsale, FinalizableCrowdsale, WhitelistedCrowdsale, IncreasingPriceCrowdsale {
  using SafeMath for uint256;

  struct ShareHolder {
    uint256 percentage;
    address wallet;
  }

  // Constant parameters assigned only once in constructor or setter
  uint256 public MIN_TOKENS_TO_PURCHASE;
  uint256 public ICO_TOKENS_CAP;
  uint256 public ICO_PERCENTAGE;
  uint256 public PHASE_LENGTH;
  uint256 public TOTAL_SHARE_HOLDERS;
  uint256[] public RATES;
  mapping(uint256 => ShareHolder) public SHARE_HOLDERS;

  // Info that gets set during execution
  bool public isShareHoldersSet = false;
  uint256 public finalizedTime;

  function TokenCrowdsale(uint256[] _rates, address _wallet, Token _token,
    uint256 _phaseLength, uint256 _cap, uint256 _minTokensToPurchase,
    uint256 _icoPercentage, uint256 _startTime) public
    Crowdsale(_rates[0], _wallet, _token)
    TimedCrowdsale(_startTime, _startTime.add(_phaseLength.mul(1 days).mul(_rates.length)))
    IncreasingPriceCrowdsale(_rates[0], _rates[_rates.length - 1]) {
      require(_minTokensToPurchase > 0);
      require(_cap > 0);
      require(_phaseLength > 0);
      require(_icoPercentage > 0);

      PHASE_LENGTH = _phaseLength;
      MIN_TOKENS_TO_PURCHASE = _minTokensToPurchase;
      ICO_TOKENS_CAP = _cap;
      ICO_PERCENTAGE = _icoPercentage;
      RATES = _rates;
  }

  function setShareHolders(uint256[] _percentages, address[] _wallets) onlyOwner public {
    require(_percentages.length == _wallets.length);
    require(!isShareHoldersSet);
    TOTAL_SHARE_HOLDERS = _wallets.length;

    uint256 _totalPercentage = ICO_PERCENTAGE;
    for(uint256 i = 0; i < TOTAL_SHARE_HOLDERS; i++) {
      SHARE_HOLDERS[i] = ShareHolder(_percentages[i], _wallets[i]);
      _totalPercentage += _percentages[i];
    }
    require(_totalPercentage == 100);
    isShareHoldersSet = true;
  }

  function hasClosed() public view returns (bool) {
    return super.hasClosed() || token.totalSupply() >= ICO_TOKENS_CAP;
  }

  function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
    super._preValidatePurchase(_beneficiary, _weiAmount);
    require(token.totalSupply() < ICO_TOKENS_CAP);

    uint256 _tokenAmount = _getTokenAmount(_weiAmount);
    if (token.totalSupply().add(_tokenAmount) > ICO_TOKENS_CAP) {
        uint256 _rate = getCurrentRate();
        uint256 _weiReq = ICO_TOKENS_CAP.sub(token.totalSupply()).mul(_rate);
        msg.sender.send(_weiAmount.sub(_weiReq));
        //overflower = _beneficiary;
    } else {
      require(_tokenAmount >= MIN_TOKENS_TO_PURCHASE);
    }
  }

  function _getTokenAmount(uint256 _weiAmount) internal view returns (uint256) {
    uint256 _tokenAmount = super._getTokenAmount(_weiAmount);
    if (token.totalSupply().add(_tokenAmount) <= ICO_TOKENS_CAP) {
      return _tokenAmount;
    }
    return ICO_TOKENS_CAP.sub(token.totalSupply());
  }

  function getCurrentRate() public view returns (uint256) {
    uint256 diff = block.timestamp.sub(openingTime);
    uint256 phase = diff.div(PHASE_LENGTH.mul(1 days));
    return RATES[phase];
  }

  function finalization() internal {
    require(finalizedTime == 0);
    require(isShareHoldersSet);

    Token _token = Token(token);

    // assign each counterparty their share
    uint256 _tokenCap = _token.totalSupply().mul(100).div(ICO_PERCENTAGE);
    for(uint256 i = 0; i < TOTAL_SHARE_HOLDERS; i++) {
      require(_token.mint(SHARE_HOLDERS[i].wallet, _tokenCap.mul(SHARE_HOLDERS[i].percentage).div(100)));
    }

    // mint and burn all leftovers
    uint256 _tokensToBurn = _token.cap().sub(_token.totalSupply());
    require(_token.mint(address(this), _tokensToBurn));
    _token.burn(_tokensToBurn);

    require(_token.finishMinting());
    _token.transferOwnership(wallet);

    finalizedTime = block.timestamp;
  }
}
