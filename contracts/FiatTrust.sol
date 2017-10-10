pragma solidity ^0.4.15;

import './FiatTrustCustodian.sol';
import './DateTimeAPI.sol';
import './ERC20.sol';
import './SafeMath.sol';

contract FiatTrust {
  using SafeMath for uint256;


  /**
   * @dev The Payou Event notifies the network of a payout
   */
  event PayOut(
    address indexed token,
    uint256 amount,
    address indexed owner
  );

  /**
   * @dev Liquidation events are called when a trust is liquidated due to lack of custodian activity
   */
  event Liquidation(
    address indexed token,
    uint256 amount,
    address indexed owner
  );

  /**
   * @dev FeePaid notifies the network that a fee has been paid
   */
  event FeePaid(
    address indexed paidTo,
    uint256 amount
  );

  /**
   * @dev Notifies the network that a redemption request was requested befor the conversion factors were filed.
   */
  event PayoutWarning(
      address indexed token,
      bytes32 indexed currency,
      uint256 factor,
      uint256 timestamp,
      uint256 tardiness
      );

  /**
   * @dev fee factor stores the denominator used to calculate payout fees
   */
  uint32 public feeFactor = 50; //2% is default

  /**
   * @dev stores the denominator used to calculate franchisee payouts
   */
  uint32 public franchiseeFactor = 10; //10% is default

  /**
   * @dev stores the maxFee that can be charged on a payout
   */
  uint32 public maxFee;

  /**
   * @dev the length of the contract in months
   */
  uint32 public term;

  /**
   * @dev the current term awaiting payout
   */
  uint32 public currentTerm;

  /**
   * @dev the current term awaiting payout
   */
  uint32 public fiatTrustVersion = 1;


  /**
   * @dev trust can be unlocked by the backup address so that the custodian can recover the account
   */
  bool public bUnlocked = false;

  /**
   * @dev stores if the trust has been started and is active
   */
  bool public bActive;


  /**
   * @dev the owner of the contract
   */
  address public owner;

  /**
   * @dev an address that can do recovery on the trust
   */
  address public backupOwner;

  /**
   * @dev the custodian of the account
   */
  address public custodian;

  /**
   * @dev the francisee that issued the account
   */
  address public franchisee;

  /**
   * @dev the token that the contract tracks
   */
  address public token;

  /**
   * @dev defines a token that a custodian owner can upgrade to
   */
  address public altToken;

  /**
   * @dev an address that payouts will goto if set
   */
  address public beneficiary;

  /**
   * @dev the hardcoded eth token
   */
  address public ethToken = 0x9999997B80f9543671b44D5119a344455e0fBe3C;

  /**
   * @dev the fiat currency that the turst tracks
   */
  bytes32 public currency;

  /**
   * @dev the fiat payout that the turst pays per term
   */
  uint256 public fiatPayout;

  /**
   * @dev tracks the date the contract started
   */
  uint256 public contractStart;

  /**
   * @dev the locks changing the benificiary until a timestamp is reached
   */
  uint256 public beneficiaryLock;


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner or custodian
   */
  modifier onlyOwnerOrCustodianOwner() {
    require(msg.sender == owner || msg.sender == CustodianOwner());
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner or custodian
   */
  modifier onlyOwnerOrCustodianOwnerOrBeneficiary() {
    require(msg.sender == owner || msg.sender == CustodianOwner() || msg.sender == beneficiary);
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner or franchisee
   */
  modifier onlyOwnerOrFranchiseeOrCustodian() {
    require(msg.sender == owner || msg.sender == franchisee || msg.sender == CustodianOwner());
    _;
  }

  /**
   * @dev Throws if the contract is active
   */
  modifier onlyInactive() {
    require(bActive == false);
    _;
  }



  /**
   * @dev constructor used to initiate the contract
   * @param _owner - the address you want to own the contract
   * @param _custodian - the custodian issueing conversion rates
   * @param _token - the token to pay out in
   * @param _currency - the currency to track
   * @param _term - the number of months to pay out
   * @param _fiatPayout - amount of fiat to pay out
   */
  function FiatTrust(address _owner,
                      address _custodian,
                      address _token,
                      bytes32 _currency,
                      uint32 _term,
                      uint256 _fiatPayout){


    custodian = _custodian;
    owner = _owner;
    token = _token;
    currency = _currency;
    term = _term;
    fiatPayout = _fiatPayout;

    FiatTrustCustodian ftc = FiatTrustCustodian(custodian);

    //cant create a trust we've never filed a conversion for
    require(ftc.getMaxConversionDate(_token,_currency) != 0 );

    if(feeFactor != ftc.feeFactor()){
      feeFactor = ftc.feeFactor();
    }
    if(franchiseeFactor != ftc.franchiseeFactor()){
      franchiseeFactor = ftc.franchiseeFactor();
    }
    if(maxFee != ftc.maxFee(currency)){
      maxFee = ftc.maxFee(currency);
    }
  }

  function CustodianOwner() constant returns(address){
    return FiatTrustCustodian(custodian).owner();
  }


  /**
   * @dev Starts out the trust and pays the origination fee
   */
  function StartTrust() onlyOwner onlyInactive returns(bool){

    //set the current term to 1
    currentTerm = 1;
    contractStart = now;
    bActive = true;
    //calculate the fee required
    FiatTrustCustodian ftc = FiatTrustCustodian(custodian);
    uint256 feeTimestamp = ftc.getMaxConversionDate(ethToken,currency);

    //cant start a trust before first conversion is filed for ETH
    require(feeTimestamp != 0);
    uint256 ethPayoutFactor = ftc.GetConversionByTimestamp(ethToken, currency, feeTimestamp);


    uint32 orginationFee = ftc.originationFee(currency);
    uint256 fee = (ethPayoutFactor * orginationFee) / (10**18);
    require(this.balance >= fee);
    PayFee(fee);

  }

  /**
   * @dev the fallback function will make a deposit
   */
  function () payable{
  }

  /**
   * @dev tells us what date we can call the withdraw function
   */
  function NextWithdraw() constant returns(uint){
    FiatTrustCustodian ftc = FiatTrustCustodian(custodian);
    uint256 PeriodLength = ftc.Period() ;
    uint256 secondsAfter1970 = contractStart.add(PeriodLength.mul(currentTerm));
    return secondsAfter1970;
  }

  /**
   * @dev calculates a payout given a payout factor for this trust
   * @param payoutFactor - the payout factor the calculation
   */
  function CalculateBasePayout(uint256 payoutFactor) constant returns(uint256){
    return payoutFactor.mul(fiatPayout) / (10**18);
  }

  /**
   * @dev calculates the maxfee given a payout factor
   * @param payoutFactor - the payout factor the calculation
   */
  function CalculateMaxFee(uint256 payoutFactor) constant returns(uint256){
    return (payoutFactor * maxFee) / (10**18);
  }


  /**
   * @dev withdraws the current periods funds
   */
  function Withdraw() onlyOwnerOrCustodianOwnerOrBeneficiary returns(bool ok){
    uint256 validDraw = NextWithdraw();

    require(bActive == true && currentTerm <= term && now > validDraw);

    //calculate payout

    uint256 payoutFactor = FiatTrustCustodian(custodian).GetConversionByTimestamp(token, currency, validDraw);

    uint256 ethPayoutFactor = 0;


    if(token != ethToken){
      ethPayoutFactor = FiatTrustCustodian(custodian).GetConversionByTimestamp(ethToken, currency, validDraw);
    } else{
      ethPayoutFactor = payoutFactor;
    }

    if(payoutFactor == 0 || ethPayoutFactor == 0){
      if(payoutFactor == 0){
        PayoutWarning(token, currency, payoutFactor, validDraw, now - validDraw);
      }
      if(ethPayoutFactor == 0){
        PayoutWarning(ethToken, currency, ethPayoutFactor, validDraw, now - validDraw);
      }


      //note: we can't hit this code unless now > validDraw so this is safe, if we don't have that check
      //then this could get triggerd at any time.
      if(now - 5 days > validDraw){
        FreeLiquidate(owner);
        return true;
      }
      else{
        return false;
      }

    }

    address payoutAddress = owner;
    if(beneficiary != 0){
      payoutAddress = beneficiary;
    }

    //payout may not be more than balance / term or the account has been underfunded
    //if it is then use the lower calculatio
    uint256 thisPayout = CalculateBasePayout(payoutFactor);
    uint256 fee = CalculateMaxFee(ethPayoutFactor);

    //set these now to avoid reentrance
    uint32 thisTerm = currentTerm;
    currentTerm = currentTerm + 1;
    if (currentTerm > term){
      bActive = false;
    }


    if(token == ethToken){
      //this branch processes ETH based trusts

      //if the fee should be less than max fee, calculate it here
      if(fee > thisPayout / feeFactor){
        fee = thisPayout / feeFactor;
      }

      //if there is not enough eth to cover the full payout + fees, parse out the remaining over the remaining terms
      if(thisPayout + fee >= (this.balance / ((term - thisTerm) + 1 ) )){
        thisPayout = (this.balance.sub(fee * ((term - thisTerm) + 1 ) ) )  / ((term - thisTerm) + 1 );
        fee = thisPayout / feeFactor;
      }


      payoutAddress.transfer(thisPayout);
      PayFee(fee);
      PayOut(ethToken, thisPayout, payoutAddress);
    }
    else{
      //this branch process ERC20 based trusts
      uint256 tokenBalance = ERC20(token).balanceOf(address(this));
      if(thisPayout >= (tokenBalance / ((term - thisTerm) + 1))){
        //reduce the payout to equal installmants if there is not enough to payout
        thisPayout = tokenBalance / ((term - thisTerm) + 1);
      }

      //convert the fee into eth
      if ((((thisPayout.mul(10**18)) / feeFactor)  / payoutFactor) < maxFee){
        fee = (((thisPayout.mul(10**18).mul(ethPayoutFactor)) / feeFactor)  / payoutFactor)  / 10**18;
      }

      ERC20(token).transfer(payoutAddress, thisPayout);
      PayFee(fee);
      PayOut(token, thisPayout, payoutAddress);
    }



    return true;

  }


  /**
   * @dev Liquidates the trust back to the owner
   */
  function FreeLiquidate(address _address) internal{
    require(_address != 0);//make sure we don't burn tokens

    uint256 payout = 0;
    if(token == ethToken){

      payout = this.balance;
      _address.transfer(payout);
      Liquidation(ethToken, payout, _address);
    }
    else{
      payout = ERC20(token).balanceOf(address(this));

      ERC20(token).transfer(_address, payout);
      Liquidation(token, payout, _address);
    }

    bActive = false;
  }


  /**
   * @dev Pays the fees to the custodian and francisee
   */
  function PayFee(uint256 _feeAmount) internal{
    if(custodian == franchisee || franchisee == 0){
      custodian.transfer(_feeAmount);
      FeePaid(custodian, _feeAmount);
    }
    else{
      custodian.transfer( (_feeAmount / franchiseeFactor).mul(franchiseeFactor - 1 ) );
      FeePaid(custodian, (_feeAmount / franchiseeFactor).mul(franchiseeFactor - 1) );
      franchisee.transfer(_feeAmount / franchiseeFactor);
      FeePaid( custodian, _feeAmount / franchiseeFactor);
    }
  }


  /**
   * @dev closes out the address and forwards all remaning assets to the final payout address
   * @param _finalPayoutAddress - address to send the funds to.
   */
  function CloseTrust(address _finalPayoutAddress) onlyOwner returns (bool){
    require(_finalPayoutAddress != 0x0); //dont accidentally burn ether or tokens
    require(currentTerm > term);
    //send all eth
    _finalPayoutAddress.transfer(this.balance);
    if(token != ethToken){
      uint256 tokenBalance = ERC20(token).balanceOf(address(this));
      ERC20(token).transfer(_finalPayoutAddress, tokenBalance);
    }
    bActive = false;
    return true;

  }

  /**
   * @dev updates the backup address that can recover the trust
   * @param _backup - address to give permissions to.
   */
  function UpdateBackup(address _backup) onlyOwner returns(bool){
    require(_backup != 0);
    backupOwner = _backup;
  }

  /**
   * @dev updates the alt token that a custdian can upgrade the contract to
   * @param _token - _token to give permissions to.
   */
  function UpdateAltToken(address _token) onlyOwner returns(bool){
    altToken = _token;
  }


  /**
   * @dev Lets the owner or franchisee set the franchisee
   * @param _franchisee -
   */
  function UpdateFranchisee(address _franchisee) onlyOwnerOrFranchiseeOrCustodian returns(bool){
    require(_franchisee != 0);
    if(msg.sender == owner && bActive == true) require(false); //owner can't set franchisee after the trust is started
    if(msg.sender == CustodianOwner() && bActive == true) require(false); //custodian can't set franchisee after the contract starts
    franchisee = _franchisee;
    return true;
  }

  /**
   * @dev updates the custodian address upon custodian upgrade. Limited to custodian owner
   * @param _custodian - address to set the custodian to.
   */
  function UpdateCustodian(address _custodian) returns(bool){
    assert(_custodian != 0);
    require(msg.sender == CustodianOwner());
    custodian = _custodian;
    return true;
  }

  /**
   * @dev updates the owner of the trust
   * @param _owner - The new owner of the trust
   */
  function UpdateOwner(address _owner) returns(bool){
    require(_owner != 0);
    require( (msg.sender == CustodianOwner() && bUnlocked == true) || (msg.sender == owner));

    owner = _owner;
    return true;
  }

  /**
   * @dev updates the token if the ERC20 contract changes
   * @param _token - The new token to track
   */
  function UpdateToken(address _token) returns(bool){
    require(_token != 0);
    require(msg.sender == CustodianOwner() && altToken == _token);
    token = _token;
    altToken = 0x0;
    return true;

  }

  /**
   * @dev unlocks or relocks the account
   * @param _unlock - value of the unlock
   */
  function UpdateUnlock(bool _unlock) returns(bool){
    require(msg.sender == backupOwner);

    bUnlocked = _unlock;
    return true;

  }

  /**
   * @dev changes the Beneficiary
   * @param _beneficiary - person
   */
  function ChangeBeneficiaryOwner(address _beneficiary) onlyOwner returns(bool){
    if(beneficiary == 0){
      beneficiary = _beneficiary;
      return true;
    }
    if(beneficiaryLock == 0){
      beneficiaryLock = now + (36 days);
      return true;
    }
    else{
      if(beneficiaryLock > now){
        beneficiary = _beneficiary;
        beneficiaryLock = 0;
        return true;
      } else {
        return false;
      }
    }
  }

  /**
   * @dev changes the Beneficiary instantly
   * @param _beneficiary - person
   */
  function ChangeBeneficiary(address _beneficiary)  returns(bool){
    require(_beneficiary != 0);
    require(msg.sender == beneficiary);
    beneficiary = _beneficiary;
  }


  /**
   * @dev changes the Beneficiary instantly
   * @param _newTrust - person
   */
  function UpgradeTo(address _newTrust) onlyOwner returns(bool){

    require(_newTrust != 0);
    // copy all variables to the trust
    FiatTrust newTrust = FiatTrust(_newTrust);
    newTrust.DoUpgrade(address(this));
    //send relevant assets to the new trust
    FreeLiquidate(_newTrust);
  }

  /**
   * @dev changes the Beneficiary instantly
   * @param _oldTrust - trust to copy
   */
  function DoUpgrade(address _oldTrust)  returns(bool){

    //this code is included as an exampl of how the next version of the contract would implement an upgrade

    FiatTrust oldTrust = FiatTrust(_oldTrust);
    FiatTrustCustodian ftc = FiatTrustCustodian(custodian);

    //authorize upgrade with custodian
    require(ftc.authorizedTrustUpgrade(_oldTrust) == address(this));

    require(owner == oldTrust.owner());  //custodian can only upgrade contracts to same owner
    require(token == oldTrust.token());  //must use same token
    require(beneficiary == oldTrust.beneficiary());  //must use same beneficiary
    require(currency == oldTrust.currency());  //must use same currency
    require(fiatPayout == oldTrust.fiatPayout()); //must use same payout
    term = oldTrust.term();
    currentTerm = oldTrust.currentTerm();
    bActive = oldTrust.bActive();
    franchisee = oldTrust.franchisee();//cant use upgrade to change francisee
    contractStart = oldTrust.contractStart();

  }

  /**
   * @dev lets the owner feely move tokens through the contract that aren't part of the trust
   * @param erc20Address - the token in the contract that shouldnt be here
   * @param destination - the place to put the tokens
   * @param amount - amount of tokens to send
   */
  function TransferTokens(address erc20Address, address destination, uint256 amount) onlyOwner returns(bool){
    require(erc20Address != token); // cant transfer token if it is the trust token
    if(erc20Address == ethToken){
      require(this.balance > amount);
      destination.transfer(amount);
      return true;
    }
    else{
      require(ERC20(erc20Address).balanceOf(address(this)) >= amount);
      ERC20(erc20Address).transfer(destination, amount);
      return true;
    }
  }
}
