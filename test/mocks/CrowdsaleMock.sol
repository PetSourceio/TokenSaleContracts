pragma solidity ^0.4.18;

import './../../contracts/Crowdsale.sol';

contract CrowdsaleMock is Crowdsale {

  uint256 private currentTime;

  function CrowdsaleMock(address _wallet, address _platform, HardcapToken _token) public
    Crowdsale(_wallet, _platform, _token) {
  }

  function setCurrentTime(uint256 _currentTime) public {
    currentTime = _currentTime;
  }

  function _getTime() internal view returns (uint256) {
    return currentTime;
  }
}
