pragma solidity ^0.4.15;

import './FiatTrust.sol';

contract FiatTrustFactory {

  address public owner;
  address public custodian;

  function FiatTrustFactory(address _custodian){
    owner = msg.sender;
    custodian = _custodian;
  }

  function CreateTrust(address _owner, address _token, bytes32 _currency, uint32 _term, uint256 _fiatPayout) returns(address){
    FiatTrust newContract = new FiatTrust(_owner, custodian, _token, _currency, _term, _fiatPayout);
    return address(newContract);
  }

}
