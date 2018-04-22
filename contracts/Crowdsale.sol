pragma solidity ^0.4.23;

import "zeppelin-solidity/contracts/ownership/Whitelist.sol";
import './Token.sol';

contract Crowdsale is Whitelist {
  using SafeMath for uint256;

  struct Phase {
    uint256 capTo;
    uint256 rate;
  }

  struct ShareHolder {
    uint256 percentage;
    address wallet;
  }

  // Constant parameters assigned only once in constructor or setter
  uint256 public MIN_TOKENS_TO_PURCHASE;
  uint256 public ICO_TOKENS_CAP;
  uint256 public ICO_PERCENTAGE;
  uint256 public ICO_START_TIME;
  uint256 public FINAL_CLOSING_TIME;
  uint256 public PHASE_LENGTH;
  uint256 public TOTAL_PHASES;
  uint256 public TOTAL_SHARE_HOLDERS;
  address public WALLET;
  Token public TOKEN;

  mapping(uint256 => Phase) public phases;
  mapping(uint256 => ShareHolder) public shareHolders;

  // changing parameters
  uint256 public phase = 0;
  uint256 public phaseClosingTime = 0;

  uint256 public weiRaised = 0;

  bool public isFinalized = false;
  bool public isShareHoldersSet = false;

  uint256 public finalizedTime;

  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

  event Finalized();

  function Crowdsale(uint256[] _phaseCaps, uint256[] _phaseRates, uint256 _phaseLength, address _wallet,
    uint256 _cap, Token _token, uint256 _minTokensToPurchase, uint256 _icoPercentage, uint256 _startTime) public {

      require(_wallet != address(0));
      require(_token != address(0));
      require(_phaseCaps.length > 0);
      require(_minTokensToPurchase > 0);
      require(_cap > 0);
      require(_phaseLength > 0);
      require(_phaseCaps.length == _phaseRates.length);

      WALLET = _wallet;
      TOKEN = _token;
      PHASE_LENGTH = _phaseLength;
      MIN_TOKENS_TO_PURCHASE = _minTokensToPurchase;
      ICO_TOKENS_CAP = _cap;
      ICO_PERCENTAGE = _icoPercentage;
      TOTAL_PHASES = _phaseCaps.length;

      for(uint256 i = 0; i < TOTAL_PHASES; i++) {
        phases[i] = Phase(_phaseCaps[i], _phaseRates[i]);
      }

      if (_startTime > 0) {
        ICO_START_TIME = _startTime;
        FINAL_CLOSING_TIME = ICO_START_TIME += PHASE_LENGTH * 1 days * TOTAL_PHASES;
      }
  }

  function startIco() onlyOwner public {
    require(ICO_START_TIME == 0);
    ICO_START_TIME = _getTime();
    FINAL_CLOSING_TIME = ICO_START_TIME += PHASE_LENGTH * 1 days * TOTAL_PHASES;
  }

  function () external payable {
    buyTokens(msg.sender);
  }

  function setShareHolders(uint256[] _percentages, address[] _wallets) onlyOwner public {
    require(_percentages.length == _wallets.length);
    require(!isShareHoldersSet);
    TOTAL_SHARE_HOLDERS = _wallets.length;

    uint256 _totalPercentage = ICO_PERCENTAGE;
    for(uint256 i = 0; i < TOTAL_SHARE_HOLDERS; i++) {
      shareHolders[i] = ShareHolder(_percentages[i], _wallets[i]);
      _totalPercentage += _percentages[i];
    }
    require(_totalPercentage == 100);
    isShareHoldersSet = true;
  }

  function buyTokens(address _beneficiary) onlyWhitelisted public payable {
    _processTokensPurchase(_beneficiary, msg.value);
  }

  function finalize() onlyOwner public {
    require(!isFinalized);
    require(_hasClosed());
    require(finalizedTime == 0);

    Token _token = Token(TOKEN);

    // assign each counterparty their share
    uint256 _tokenCap = _token.totalSupply().mul(100).div(ICO_PERCENTAGE);
    for(uint256 i = 0; i < TOTAL_SHARE_HOLDERS; i++) {
      require(_token.mint(shareHolders[i].wallet, _tokenCap.mul(shareHolders[i].percentage).div(100)));
    }

    // mint and burn all leftovers
    uint256 _tokensToBurn = _token.cap().sub(_token.totalSupply());
    require(_token.mint(address(this), _tokensToBurn));
    _token.burn(_tokensToBurn);

    require(_token.finishMinting());
    _token.transferOwnership(WALLET);

    Finalized();

    finalizedTime = _getTime();
    isFinalized = true;
  }

  function _hasClosed() internal view returns (bool) {
    return _getTime() > FINAL_CLOSING_TIME || TOKEN.totalSupply() >= ICO_TOKENS_CAP;
  }

  function _processTokensPurchase(address _beneficiary, uint256 _weiAmount) internal {
    _preValidatePurchase(_beneficiary, _weiAmount);

    // calculate token amount to be created
    uint256 _leftowers = 0;
    uint256 _weiReq = 0;
    uint256 _weiSpent = 0;
    uint256 _tokens = 0;
    uint256 _currentSupply = TOKEN.totalSupply();
    bool _phaseChanged = false;
    Phase memory _phase = phases[phase];

    while (_weiAmount > 0 && _currentSupply < ICO_TOKENS_CAP) {
      _leftowers = _phase.capTo.sub(_currentSupply);
      _weiReq = _leftowers.div(_phase.rate);
      // check if it is possible to purchase more than there is available in this phase
      if (_weiReq < _weiAmount) {
         _tokens = _tokens.add(_leftowers);
         _weiAmount = _weiAmount.sub(_weiReq);
         _weiSpent = _weiSpent.add(_weiReq);
         phase = phase + 1;
         _phaseChanged = true;
      } else {
         _tokens = _tokens.add(_weiAmount.mul(_phase.rate));
         _weiSpent = _weiSpent.add(_weiAmount);
         _weiAmount = 0;
      }

      _currentSupply = TOKEN.totalSupply().add(_tokens);
      _phase = phases[phase];
    }

    require(_tokens >= MIN_TOKENS_TO_PURCHASE);

    // if phase changes forward the date of the next phase change by phaseLength days
    if (_phaseChanged) {
      _changeClosingTime();
    }

    // return leftovers to investor if tokens are over but he sent more ehters.
    if (msg.value > _weiSpent) {
      uint256 _overflowAmount = msg.value.sub(_weiSpent);
      _beneficiary.transfer(_overflowAmount);
    }

    weiRaised = weiRaised.add(_weiSpent);

    require(Token(TOKEN).mint(_beneficiary, _tokens));
    TokenPurchase(msg.sender, _beneficiary, _weiSpent, _tokens);

    // You can access this method either buying tokens or assigning tokens to
    // someone. In the previous case you won't be sending any ehter to contract
    // so no need to forward any funds to wallet.
    if (msg.value > 0) {
      WALLET.transfer(_weiSpent);
    }
  }

  function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
    // if the phase time ended calculate next phase end time and set new phase
    if (phaseClosingTime < _getTime() && phaseClosingTime < FINAL_CLOSING_TIME && phase < TOTAL_PHASES) {
      phase = phase.add(_calcPhasesPassed());
      _changeClosingTime();

    }
    require(_getTime() >= ICO_START_TIME && _getTime() <= phaseClosingTime);
    require(_beneficiary != address(0));
    require(_weiAmount != 0);
    require(phase <= 8);

    require(TOKEN.totalSupply() < ICO_TOKENS_CAP);
    require(!isFinalized);
  }

  function _changeClosingTime() internal {
    phaseClosingTime = _getTime() + PHASE_LENGTH * 1 days;
    if (phaseClosingTime > FINAL_CLOSING_TIME) {
      phaseClosingTime = FINAL_CLOSING_TIME;
    }
  }

  function _calcPhasesPassed() internal view returns(uint256) {
    return  _getTime().sub(phaseClosingTime).div(PHASE_LENGTH * 1 days).add(1);
  }

 function _getTime() internal view returns (uint256) {
   return now;
 }

}
