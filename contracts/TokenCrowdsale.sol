pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/crowdsale/validation/WhitelistedCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/price/IncreasingPriceCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/emission/MintedCrowdsale.sol";
import "zeppelin-solidity/contracts/crowdsale/distribution/FinalizableCrowdsale.sol";
import './Token.sol';

contract TokenCrowdsale is MintedCrowdsale, FinalizableCrowdsale, WhitelistedCrowdsale, IncreasingPriceCrowdsale {
  using SafeMath for uint256;

  // Struct containing shareholder info
  struct ShareHolder {
    uint256 percentage;
    address wallet;
  }

  // Constant parameters assigned only once in constructor or setter

  // Parameter to forbid to purchase less than this tokens
  uint256 public MIN_TOKENS_TO_PURCHASE;

  // ICO tokens cap. NOTE - this cap should include pre-ico. Otherwise contract may not work as expected
  uint256 public ICO_TOKENS_CAP;

  // Number shows how much percentage ICO + preICO makes out of total cap
  uint256 public ICO_PERCENTAGE;

  // Parameter shows how long does one phase last
  uint256 public PHASE_LENGTH;

  // Parameter shows number of shareholders
  uint256 public TOTAL_SHARE_HOLDERS;

  // Parameter holds rates in different phases
  uint256[] public RATES;

  // Mapping holds shareholders information
  mapping(uint256 => ShareHolder) public SHARE_HOLDERS;


  // Parameters that gets set during execution

  // Allows set shareholders to be set only once
  bool public isShareHoldersSet = false;

  // Time when contract is finalized
  uint256 public finalizedTime;

  // Most of the params are what their name indicates
  // NOTE: _cap is ICO + pre-ICO cap
  // NOTE: _icoPercentage is ICO + pre-ICO percentage out of total cap
  function TokenCrowdsale(uint256[] _rates, address _wallet, Token _token,
    uint256 _phaseLengthInDays, uint256 _cap, uint256 _minTokensToPurchase,
    uint256 _icoPercentage, uint256 _startTime) public
    Crowdsale(_rates[0], _wallet, _token)
    TimedCrowdsale(_startTime, _startTime.add(_phaseLengthInDays.mul(1 days).mul(_rates.length)))
    IncreasingPriceCrowdsale(_rates[0], _rates[_rates.length - 1]) {
      require(_minTokensToPurchase > 0);
      require(_cap > 0);
      require(_phaseLengthInDays > 0);
      require(_icoPercentage > 0);

      PHASE_LENGTH = _phaseLengthInDays.mul(1 days);
      MIN_TOKENS_TO_PURCHASE = _minTokensToPurchase;
      ICO_TOKENS_CAP = _cap;
      ICO_PERCENTAGE = _icoPercentage;
      RATES = _rates;
  }

  // Custom method for setting shareholders that after finalization receive their share (percentage) in tokens.
  // This can't be set in constructor because there are shareholders that has their tokens locked in
  // token holder wallets. Those wallets needs to know about crodsale and are created first.
  function setShareHolders(uint256[] _percentages, address[] _wallets) onlyOwner public {
    require(_percentages.length == _wallets.length);
    require(!isShareHoldersSet);
    TOTAL_SHARE_HOLDERS = _wallets.length;

    uint256 _totalPercentage = ICO_PERCENTAGE;
    for(uint256 i = 0; i < TOTAL_SHARE_HOLDERS; i++) {
      SHARE_HOLDERS[i] = ShareHolder(_percentages[i], _wallets[i]);
      _totalPercentage = _totalPercentage.add(_percentages[i]);
    }
    // It should be distributed 100 percent tokens
    require(_totalPercentage == 100);
    isShareHoldersSet = true;
  }

  // OpenZeppelin FinalizableCrowdsale method override
  // adds functionality to check either date is closed or all tokens are sold
  function hasClosed() public view returns (bool) {
    return super.hasClosed() || token.totalSupply() >= ICO_TOKENS_CAP;
  }

  // OpenZeppelin Crodsale and others base contracts method override
  // Adds token cap validation, min req purchase token validation.
  // Also if investor buys last tokens - returns overflow amount of wei
  function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
    super._preValidatePurchase(_beneficiary, _weiAmount);
    require(token.totalSupply() < ICO_TOKENS_CAP);

    uint256 _tokenAmount = _getTokenAmount(_weiAmount);
    if (token.totalSupply().add(_tokenAmount) > ICO_TOKENS_CAP) {
        uint256 _rate = getCurrentRate();
        uint256 _weiReq = ICO_TOKENS_CAP.sub(token.totalSupply()).mul(_rate);
        msg.sender.send(_weiAmount.sub(_weiReq));
    } else {
      require(_tokenAmount >= MIN_TOKENS_TO_PURCHASE);
    }
  }

  // OpenZeppelin Crodsale and others base contracts method override
  // Adds functionality that investor could buy last tokens
  function _getTokenAmount(uint256 _weiAmount) internal view returns (uint256) {
    uint256 _tokenAmount = super._getTokenAmount(_weiAmount);
    if (token.totalSupply().add(_tokenAmount) <= ICO_TOKENS_CAP) {
      return _tokenAmount;
    }
    return ICO_TOKENS_CAP.sub(token.totalSupply());
  }

  // OpenZeppelin IncreasingPriceCrowdsale method override
  // Adds functionality to calculate rate by date using steps
  function getCurrentRate() public view returns (uint256) {
    uint256 diff = block.timestamp.sub(openingTime);
    uint256 phase = diff.div(PHASE_LENGTH);
    return RATES[phase];
  }

  // OpenZeppelin FinalizableCrowdsale method override
  // Adds functionality of burining leftovers
  // Also distributing tokens to shareholders and reassining token ovnership
  function finalization() internal {
    // allow finalize only once and require data to be set
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
