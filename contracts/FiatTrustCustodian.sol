pragma solidity ^0.4.15;

import './FiatTrustFactory.sol';
import './DateTimeAPI.sol';
import './ERC20.sol';
import './SafeMath.sol';
import './iLicensor.sol';
import './TrustStorage.sol';

contract FiatTrustCustodian {
  using SafeMath for uint256;

  event TrustCreated(
    address indexed owner,
    address indexed location
  );

  event ConversionSet(
    address indexed token,
    bytes32 indexed currency,
    uint year,
    uint month,
    uint day,
    uint payout
  );

  event NewMaxConversion(
    address indexed token,
    bytes32 indexed currency,
    uint256 indexed timestamp
  );

  /**
   * @dev Upon each withdrawl an amount equal to the payout / the fee factor is sent to the custodian.
   */
  uint32 public feeFactor = 50; //0.5% is default

  /**
   * @dev A franchisee can get 10% of the fee if set up
   */
  uint32 public franchiseeFactor = 10; //10% is default

  /**
   * @dev payouts max
   */
  mapping(bytes32 => uint32) public maxFee;

  /**
   * @dev Trusts cost originationFee dollarsto set up
   */
  mapping(bytes32 => uint32) public originationFee;

  /**
   * @dev custodian must authorize a trust upgrade
   */
  mapping(address => address) public authorizedTrustUpgrade;

  /**
   * @dev owner of the custodian
   */
  address public owner;

  /**
   * @dev Location of the factory so we can upgrade later
   */
  address public factory;

  /**
   * @dev Location of the DateTimeLibray on the network so we can upgrade
   */
  address public dateTimeLibrary;


  /**
   * @dev vanity address used so that accidental token sends or eth sends can be refunded. Hard coded value.
   */
  address public ethToken = 0x9999997B80f9543671b44D5119a344455e0fBe3C;

  /**
   * @dev future feature will include governance
   */
  address public licensor;

  /**
   * @dev storage is held in a differenc contract for easy upgrading.
   */
  address public trustStorage;

  /**
   * @dev the address that ether fees will be swept to upon withdrawl
   */
  address public benificiary;


  /**
   * @dev agents can set conversions so that owner keys don't have to be handed out
   */
  mapping(address => bool) agent;




   /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner or an agent
   */
  modifier onlyOwnerOrAgent() {
    require(msg.sender == owner || agent[msg.sender] == true);
    _;
  }

  /**
   * @dev allow the custodian to get paid
   */
  function () payable{
  }

  /**
   * @dev constructor, sets owner
   */
  function FiatTrustCustodian(){
    owner = msg.sender;

    //the licensor api is a future feature and for now we just set this to ourselves
    licensor = address(this);
  }

  /**
   * @dev sets owner to a new value
   * @param _owner - the address you want to be the new owner
   */
  function TransferOwnership(address _owner) onlyOwner returns (bool){
    owner = _owner;
    return true;
  }

  /**
   * @dev authorize an Uprade
   * @param _oldTrust - the trust you want to upgrade
   * @param _newTrust - the new trust
   */
  function AuthorizeTrustUpgrade(address _oldTrust, address _newTrust) onlyOwner returns (bool){
    authorizedTrustUpgrade[_oldTrust] = _newTrust;
    return true;
  }

  /**
   * @dev create a new trust using the factory
   * @param _token - the token that is held to be held in the trust
   * @param _currency - the currency that the trust should convert into
   * @param _term - the number of months the trust should last
   * @param _fiatPayout - the amount of currency that should be paid out each term
   */
  function CreateTrust(address _token, bytes32 _currency, uint32 _term, uint256 _fiatPayout) returns(address){
    address newContract = FiatTrustFactory(factory).CreateTrust(msg.sender, _token, _currency, _term, _fiatPayout);
    TrustCreated(msg.sender, newContract);
    return newContract;
  }

  /**
   * @dev changes the factory used to create a new trust
   * @param _address - the address of the factory
   */
  function SetFactory(address _address) onlyOwner{
    factory = _address;
  }

  /**
   * @dev sets the date time library address
   * @param _address - the address you want to be the DateTime library
   */
  function SetDateTimeLibrary(address _address) onlyOwner{
    dateTimeLibrary = _address;
  }

  /**
   * @dev sets the storage for the contract to use to store conversion factors
   * @param _address - the address for the storage
   */
  function SetStorage(address _address) onlyOwner{
    trustStorage = _address;
  }

  /**
   * @dev sets the liscensor of the contract - currently set to self
   * @param _address - the address you want to be the liscensor
   */
  function SetLicensor(address _address) onlyOwner{
    licensor = _address;
  }

  /**
   * @dev sets the fee for starting a contract subscribed to the custodian
   * @param _currency - the currency the fee is set in
   * @param _fee - the amount is USD that the custodian charges for subscription
   */
  function SetOriginationFee(bytes32 _currency, uint32 _fee) onlyOwner{
    originationFee[_currency] = _fee;
  }

  /**
   * @dev allows the turning on and off of agents who are allowed to set prices
   * @param _agent - the address acting as an agent
   * @param _value - true or false
   */
  function SetAgent(address _agent, bool _value) onlyOwner{
    agent[_agent] = _value;
    TrustStorage(trustStorage).UpdateOwner(_agent, _value);
  }

  /**
   * @dev sets the max fee charged on a payout
   * @param _currency - the currency the fee is set in
   * @param _fee - the amount is USD that is the max the custodian charges for a payout
   */
  function SetMaxFee(bytes32 _currency, uint32 _fee) onlyOwner{
    maxFee[_currency] = _fee;
  }

  /**
   * @dev sets the denminator for the calcualation of the fee to charge on a payout
   * @param _factor - the denominator in the calculation. i.e. 200 = 1/200 = .5%
   */
  function SetFeeFactor(uint32 _factor) onlyOwner{
    feeFactor = _factor;
  }

  /**
   * @dev sets the fee cut for a franchisee if set
   * @param _factor - the denominator in the calulation. ie. 10 = 1/10 = 10%
   */
  function SetFranchiseeFactor(uint32 _factor) onlyOwner{
    franchiseeFactor = _factor;
  }

  /**
   * @dev sets the address that funds are swept to
   * @param _address - the target address
   */
  function SetCustodianBenificiary(address _address) onlyOwner{
    benificiary = _address;
  }

  /**
   * @dev returns if the custodian is liscenesd to operate or not - see iLicensor interface
   * @param _contract - the contract to check
   */
  function isAuthorized(address _contract) returns(bool){
    if(_contract != address(this)) return false;
    return true;
  }

  /**
   * @dev calculates the length of a month
   */
  function Period() constant returns (uint256 lengthOfMonth){
    //put this in a constant function so that we don't have to use storage
    //execution takes 302 gas which means calculation is more efficent in any contract under 66 months.
    //not sure about deployment costs
    //the period is about 30.66 days so that leap year is taken into account every 4 years.
    lengthOfMonth = (1 years / 12) + (1 days / 4);
    return lengthOfMonth;
  }

  /**
   * @dev allows the custodian to remove eth from the contract so as to collect fees, also can move tokens from the contract ether goes to the benificiary if set
   * @param _token - the tokens or eth to withdraw
   * @param _amount - the amount to withdraw
   */
  function Withdraw(address _token, uint256 _amount) onlyOwner {
    if(_token == ethToken){
      address destination = benificiary;
      if(benificiary == 0){
        destination = owner;
      }
      destination.transfer(_amount);
    }
    else
    {
      ERC20(_token).transfer(owner, _amount);
    }
  }


  /**
   * @dev builds a signature for storing conversion factors given a date
   * @param _token - the tokens for the conversion factor
   * @param _currency - the currency that the token is converted into
   * @param _year - the year
   * @param _month - the month
   * @param _day - the day
   */
  function BuildDateSig(address _token, bytes32 _currency, uint256 _year, uint256 _month, uint256 _day) constant returns(bytes32){
    return keccak256(_token, _currency, _year, _month, _day);
  }

  /**
   * @dev builds a signature for storing conversion factors given a date
   * @param _token - the tokens for the conversion factor
   * @param _currency - the currency that the token is converted into
   * @param _timestamp - the timestamp to be created
   */
  function BuildDateSigByTimestamp(address _token, bytes32 _currency, uint256 _timestamp) constant returns(bytes32){
    uint16 _year = DateTimeAPI(dateTimeLibrary).getYear(_timestamp);
    uint8 _month = DateTimeAPI(dateTimeLibrary).getMonth(_timestamp);
    uint8 _day = DateTimeAPI(dateTimeLibrary).getDay(_timestamp);
    return keccak256(_token, _currency, uint256(_year), uint256(_month), uint256(_day));
  }


  /**
   * @dev returns the conversion factor for the given timestamp
   * @param _token - the tokens for the conversion factor
   * @param _currency - the currency that the token is converted into
   * @param _timestamp - the timestamp to be searched
   */
  function GetConversionByTimestamp(address _token, bytes32 _currency, uint256 _timestamp) constant returns(uint){
      uint16 _year = DateTimeAPI(dateTimeLibrary).getYear(_timestamp);
      uint8 _month = DateTimeAPI(dateTimeLibrary).getMonth(_timestamp);
      uint8 _day = DateTimeAPI(dateTimeLibrary).getDay(_timestamp);
      return GetConversion(_token, _currency, uint256(_year),uint256(_month), uint256(_day));
  }


  /**
   * @dev returns a conversion factor for a given date
   * @param _token - the tokens for the conversion factor
   * @param _currency - the currency that the token is converted into
   * @param _year - the year
   * @param _month - the month
   * @param _day - the day
   */
  function GetConversion(address _token, bytes32 _currency, uint256 _year, uint256 _month, uint256 _day) constant returns (uint256){
    bytes32 sig = BuildDateSig(_token, _currency, _year, _month, _day);
    return getPayouts(sig);
  }


  /**
   * @dev sets a conversion factor for a token / currency / date triplet
   * @param _token - the tokens for the conversion factor
   * @param _currency - the currency that the token is converted into
   * @param _year - the year
   * @param _month - the month
   * @param _day - the day
   * @param _crypto - the amount of crypto that can be converted to _fiat
   * @param _fiat - the amount of fiat that amount of crypto can be converted to
   */
  function SetConversion(address _token, bytes32 _currency, uint16 _year, uint8 _month, uint8 _day, uint256 _crypto, uint256 _fiat) onlyOwnerOrAgent returns(bool){
    //must be liscensed to set conversion rates
    require(iLicensor(licensor).isAuthorized(address(this)) == true);

    uint256 ThisTimeStamp = DateTimeAPI(dateTimeLibrary).toTimestamp(_year, _month, _day);

    //make sure we cant send future conversoion factors
    require(ThisTimeStamp < now);

    bytes32 sig = BuildDateSig(_token, _currency, _year, _month, _day);
    uint256 thePayout = (_crypto.mul(10**18)) / _fiat;
    setPayouts(sig, thePayout);

    uint256 pastTimestamp = getMaxConversionDate(_token, _currency);

    if(ThisTimeStamp > pastTimestamp){
      //we need to keep track of the max conversion set for each token / currency pair
      setMaxConversionDate(_token, _currency, ThisTimeStamp);
      NewMaxConversion(_token, _currency, ThisTimeStamp);
    }
    ConversionSet(_token, _currency, _year, _month, _day, thePayout);
    return true;
  }

  /**
   * @dev returns the payout for a give token / currency / date hash
   * @param _hash - the hash to look up
   */
  function getPayouts(bytes32 _hash) constant returns(uint256){
    return TrustStorage(trustStorage).getInt(0x1, _hash);
  }

  /**
   * @dev returns the max conversion date for a given token / currency combo
   * @param _token - the token to look up
   * @param _currency - the currency to look up
   */
  function getMaxConversionDate(address _token, bytes32 _currency) constant returns(uint256){
    return TrustStorage(trustStorage).getInt(0x2, keccak256(_token,_currency));
  }

  /**
   * @dev returns the payout for a give token / currency / date hash
   * @param _hash - the hash to set
   * @param _value - the value
   */
  function setPayouts(bytes32 _hash, uint256 _value) onlyOwnerOrAgent returns(bool){
    return TrustStorage(trustStorage).putValue(0x1, _hash, bytes32(_value));
  }


  /**
   * @dev returns the max conversion date for a given token / currency combo
   * @param _token - the token to set
   * @param _currency - the currency to set
   * @param _value - the value
   */
  function setMaxConversionDate(address _token, bytes32 _currency, uint256 _value) onlyOwnerOrAgent returns(bool){
    return TrustStorage(trustStorage).putValue(0x2, keccak256(_token,_currency), bytes32(_value));
  }



}
