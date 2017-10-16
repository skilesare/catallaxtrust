pragma solidity ^0.4.15;

import './FiatTrust.sol';
import './ERC20.sol';

contract FiatTrustFactory {

  address public owner;
  address public custodian;

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Throws if called by any account other than the custodian.
   */
  modifier onlyCustodian() {
    require(msg.sender == custodian);
    _;
  }
  
  

  function FiatTrustFactory(address _custodian){
    owner = msg.sender;
    custodian = _custodian;
  }

  function CreateTrust(address _owner, address _token, bytes32 _currency, uint32 _term, uint256 _fiatPayout) onlyCustodian returns(address){
    FiatTrust newContract = new FiatTrust(_owner, custodian, _token, _currency, _term, _fiatPayout);
    return address(newContract);
  }

  /**
   * @dev allows the custodian to remove eth from the contract so as to collect fees, also can move tokens from the contract ether goes to the benificiary if set
   * @param _token - the tokens or eth to withdraw - 0 is ETH  
   * @param _destination - the place to put funds
   * @param _amount - the amount to withdraw
   */
  function Withdraw(address _token, address _destination, uint256 _amount) onlyOwner {
    if(_token == 0){
      _destination.transfer(_amount);
    }
    else
    {
      ERC20(_token).transfer(_destination, _amount);
    }
  }

}
