FiatTrustCustodian = artifacts.require('./FiatTrustCustodian.sol')
FiatTrust = artifacts.require('./FiatTrust.sol')
FiatTrustFactory = artifacts.require('./FiatTrustFactory.sol')
HumanStandardToken = artifacts.require('./HumanStandardToken.sol')
DateTime = artifacts.require('./DateTime.sol')
TokenStorage = artifacts.require('./TrustStorage.sol')
q = require('q') if !q?
accounts = []
async = require("promise-async")
ethTokenAddress = "0x9999997B80f9543671b44D5119a344455e0fBe3C"
usdCurrencybytes = web3.fromAscii('USD', 32)
tokenStartBalance = 100000 * 10**18
moment = require('moment')


prepEnvironment = (custodianOwner)->
  return new Promise (resolve, reject)->
    custodian = null
    factory = null
    token = null
    storage = null
    #Create the custodian
    FiatTrustCustodian.new(from: custodianOwner).then (instance)->
      custodian = instance
      #create the factory
      FiatTrustFactory.new(custodian.address, from: custodianOwner)
    .then (instance)->
      console.log 'new factory'
      factory = instance
      #create a datetime library(this has been published previously on mainnet so you can use one of those)
      DateTime.new(from: custodianOwner)
    .then (instance)->
      console.log 'new DateTime'
      #set the date time library
      custodian.SetDateTimeLibrary(instance.address, from: custodianOwner)
    .then (result)->
      console.log 'dt set'
      #set the factory location
      custodian.SetFactory(factory.address, from:custodianOwner)
    .then (result)->
      console.log 'factory set'
      #Create an ERC20 token to test with
      HumanStandardToken.new(tokenStartBalance,"token",0,'tkn', from: custodianOwner)
    .then (instance)->
      console.log 'new token'
      token = instance
      #create a new storage contract
      TokenStorage.new(from: custodianOwner)
    .then (instance)->
      console.log 'new storage'
      storage = instance
      #set the storage contract
      custodian.SetStorage(storage.address, from: custodianOwner)
    .then (instance) ->
      console.log 'storage set'
      #update the owner of the storage to include the custodian contract
      storage.UpdateOwner(custodian.address, true, from: custodianOwner)
    .then (instance)->
      console.log 'first conversion set'
      #set an old conversion for ETH to USD
      custodian.SetConversion(ethTokenAddress, usdCurrencybytes, 1989,1, 1, web3.toWei(0.01,"ether"),1, from: custodianOwner)
    .then (instance)->
      console.log 'conversion set'
      #set an old conversion for ERC20 token to USD
      custodian.SetConversion(token.address, usdCurrencybytes, 1989,1, 1, web3.toWei(0.01,"ether"),1, from: custodianOwner)
    .then (instance)->
      console.log 'max fee set'
      #set the max fee
      custodian.SetMaxFee(usdCurrencybytes, 50, from: custodianOwner)
    .then (instance)->
      console.log 'payout fee set'
      #set the pay fee
      custodian.SetFeeFactor(200, from: custodianOwner)
    .then (instance)->
      console.log 'origination fee set set'
      #set the origination fee
      custodian.SetOriginationFee(usdCurrencybytes, 25, from: custodianOwner)
    .then ->
      resolve
        custodian: custodian
        token: token


contract 'FiatTrust', (paccounts)->
  accounts = paccounts
  console.log accounts

  it "cant be upgraded if not authorized", ->

    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    secondTrust = null
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})
      .then (txn)->
        trustAddress = null
        txn.logs.map (o)->
          if o.event is 'TrustCreated'
            console.log 'found new Trust at' + o.args.location
            secondTrust = FiatTrust.at(o.args.location)
        console.log 'have second instance'
        console.log secondTrust.address
        assert secondTrust.address.length > 0, true, 'second trust wasnt completed'
        i.UpgradeTo(secondTrust.address, from:accounts[0])
    .then (result)->
      assert.equal false, true, 'shouldnt have been able to close trust'
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert secondTrust.address.length > 0, true, 'second trust wasnt completed'
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        console.log error
        assert(false, error.toString())
  it "can be upgraded if authorized", ->

    i = null
    lastTerm = 0
    startBalance = 0
    startBalanceTrust = 0
    custodian = null
    currentTerm = 0
    token = null
    secondTrust = null
    firstTrustMaturation = null
    firstTrustCurrentTerm = null
    firstTrustContractStart = null
    nextPayoutDate = null

    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          web3.currentProvider.sendAsync
            jsonrpc: "2.0",
            method: "evm_mine",
            id: new Date().getTime()
          , (err, value)->
            secondTrust.NextWithdraw()
            .then (result)->
              console.log 'next ' + result
              nextPayout = result.toNumber()
              aDate = nextPayout * 1000
              aDate = moment.utc(new Date(aDate))
              console.log aDate
              console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
              custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), .44 * 10**18,1000)
              .then ->
                custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
            .then (result) ->
              console.log 'about to withdraw'
              secondTrust.Withdraw(from: accounts[0])
            .then (result)->
              resolve result
            .catch (err)->
              reject err

    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      token.balanceOf(accounts[0])
    .then (result)->
      console.log 'start balance 0 ' + result.toNumber()
      startBalance = result.toNumber()
    .then (result)->
      i.NextWithdraw()


    .then (result)->
      firstTrustMaturation = result.toNumber()
      i.currentTerm()
    .then (result)->
      firstTrustCurrentTerm = result.toNumber()
      i.contractStart()
    .then (result)->
      firstTrustContractStart = result.toNumber()
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})
      .then (txn)->
        trustAddress = null
        txn.logs.map (o)->
          if o.event is 'TrustCreated'
            console.log 'found new Trust at' + o.args.location
            secondTrust = FiatTrust.at(o.args.location)
        console.log 'have second instance'
        console.log secondTrust.address
        assert secondTrust.address.length > 0, true, 'second trust wasnt completed'
        custodian.AuthorizeTrustUpgrade(i.address, secondTrust.address)
    .then (result)->
      web3.eth.sendTransaction({ from: accounts[1], to: secondTrust.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.UpgradeTo(secondTrust.address, from:accounts[0])
    .then (result)->
      token.balanceOf(secondTrust.address)
    .then (result)->
      startBalanceTrust = result.toNumber()
      console.log startBalanceTrust
      assert.equal result.toNumber(), 5000, 'tokens were not transfered'
      secondTrust.contractStart()
    .then (result)->
      assert.equal result.toNumber(), firstTrustContractStart, 'contract start didnt match'
      secondTrust.currentTerm()
    .then (result)->
      console.log 'currentterm ' + result.toNumber()
      assert.equal result.toNumber(), firstTrustCurrentTerm, 'current terms didnt match'
      secondTrust.NextWithdraw()
    .then (result)->
      nextPayoutDate = result.toNumber()
      console.log nextPayoutDate
      console.log new Date(nextPayoutDate * 1000)
      assert.equal result.toNumber(), firstTrustMaturation, 'next withdrawls dont match'
      secondTrust.fiatPayout()
    .then (result)->
      console.log result.toNumber() + ' is the payout'
      custodian.GetConversionByTimestamp(token.address,usdCurrencybytes, nextPayoutDate)
    .then (result)->
      console.log 'the conversion' + result
      #assert.equal result.toNumber(), firstTrustMaturation, 'next withdrawls dont match'
      secondTrust.CalculateBasePayout(result.toNumber())
    .then (result)->
      console.log 'fee should be '  + result.toNumber()
      secondTrust.bActive()
    .then (result)->
      console.log 'activi is '
      console.log result
      secondTrust.owner()
    .then (result)->
      console.log 'activi is '
      console.log result
      withdrawFunction(1)
    .then (result)->
      token.balanceOf(secondTrust.address)
    .then (result)->
      console.log result.toNumber()
      assert.equal result.toNumber() < startBalanceTrust, true, "token didnt withdraw"
      token.balanceOf(accounts[0])
    .catch (error)->
      assert(false, error.toString())
  it "should fail if closetrust is called before end of term for token trust", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
            .then ->
              custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
          .then (result) ->
            i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      async.eachSeries [1..4], (item, done)->
        #console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          currentTerm = result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      i.CloseTrust(accounts[0], from:accounts[0])
    .then (result)->
      assert.equal false, true, 'shouldnt have been able to close trust'
    .then (result)->
      #console.log result
      #assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.19, "ether")), true, "not enough withdrawn"
      #assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.21, "ether")), true, "too much withdrawn"
      assert.equal result.toNumber(), tokenStartBalance, "too much withdrawn"

    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        assert(false, error.toString())

  it "should not allow close trust of token trust", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), .44 * 10**18,1000)
          .then (result) ->
            i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 100, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: .44 * (10**18) })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      async.eachSeries [1..4], (item, done)->
        #console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          currentTerm = result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #should be 4976 eth left in the contract
      i.CloseTrust(accounts[0], from:accounts[0])
    .then (result)->
      #console.log 'checking balance'
      assert.equal false, true, "shouldnt have been able to close trust"

    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        assert(false, error.toString())
  it "should allow for transfer of owner", ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    custodian = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      i.UpdateOwner(accounts[2], from: accounts[0])
    .then (result)->
      i.owner()
    .then (result)->
      assert.equal result, accounts[2]
    .then (result)->
      i.UpdateOwner(accounts[4], from: accounts[0])
    .then (result)->
      assert.equal false, true, "shouldnt be here"
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        assert(false, error.toString())
  it "will liquidate without fee if conversion rate is 5 days old", ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    startTrustBalance = 0
    custodian = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      console.log result
      console.log 'sending ether'
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err, value)->
          web3.currentProvider.sendAsync
            jsonrpc: "2.0",
            method: "evm_mine",
            id: new Date().getTime()
          , (err, value)->
            console.log 'delay ran'
            console.log err
            console.log value
            tResolve true
    .then (result)->
      #console.log err
      #need to set the pay out for the example
      startBalance = web3.eth.getBalance(accounts[0])
      startCustodianBalance = web3.eth.getBalance(custodian.address)
      startTrustBalance =web3.eth.getBalance(i.address)
      console.log 'Start Balance' + startBalance
      i.NextWithdraw()
    .then (result)->
      console.log 'NextWithdraw'
      console.log new Date(result.toNumber() *1000)
      #first withdraw should be just a few days old (<5) and should just return false
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      web3.eth.getBalance(i.address)
    .then (result)->
      console.log 'moving forward another 34 days'
      assert.equal result.toNumber(),startTrustBalance, 'illegal eth transfer'
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err, value)->
          web3.currentProvider.sendAsync
            jsonrpc: "2.0",
            method: "evm_mine",
            id: new Date().getTime()
          , (err, value)->
            console.log 'delay ran'
            console.log err
            console.log value
            tResolve true
    .then (result)->
      i.Withdraw(from: accounts[0])
    .then (result)->
      web3.eth.getBalance(accounts[0])
    .then (result)->
      console.log result
      #the whole .44 eth minus gas should be returned because the conversion rate is missing
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() > startBalance.toNumber(), true, 'eth didnt transfer'
      assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.44,"ether")), true, 'too much eth transfered'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      assert.equal result.toNumber(), startCustodianBalance, 'Fee may have been paid paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'
  it "does allow liquidation of tokens if conversion isnt posted for 5 days", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    startTrustBalance = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err, value)->
          web3.currentProvider.sendAsync
            jsonrpc: "2.0",
            method: "evm_mine",
            id: new Date().getTime()
          , (err, value)->
            console.log 'delay ran'
            console.log err
            console.log value
            tResolve true
    .then (result)->
      #console.log err
      token.balanceOf(accounts[0])
    .then (result)->
      startBalance = result
      startCustodianBalance = web3.eth.getBalance(custodian.address)
      console.log 'found custodian balance' + startCustodianBalance.toNumber()
      token.balanceOf(i.address)
    .then (result)->
      startTrustBalance = result.toNumber()
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      token.balanceOf(i.address)
    .then (result)->
      console.log result
      assert.equal result.toNumber(), startTrustBalance, 'illegal token move'
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err, value)->
          web3.currentProvider.sendAsync
            jsonrpc: "2.0",
            method: "evm_mine",
            id: new Date().getTime()
          , (err, value)->
            console.log 'delay ran'
            console.log err
            console.log value
            tResolve true
    .then (result)->
      i.Withdraw(from: accounts[0])
    .then (result)->
      token.balanceOf(i.address)
    .then (result)->
      assert.equal result.toNumber(), 0, 'withdraw wasnt right'
      token.balanceOf(accounts[0])
    .then (result)->
      console.log result
      #since payout is .1 eth per usd we multiply fiatpayout 1
      #we only test .9 eth and 1.1 because gas costs weigh in
      #96 413397700000000000
      #96 502336500000000000
      #
      #console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber(), tokenStartBalance, 'token didnt liquidate'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      assert.equal result.toNumber(), startCustodianBalance, 'Fee may have been paid paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'

  it "does allow custodian to push withdrawl to owner", ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    custodian = null
    nextPayout = 0
    #console.log 'starting'
    #the only difference between this test and a later test is that we are going to allow the owner of the
    #custodian, here accoutns[1] to call withdrawl and push.  This would be needed to collect the fees in
    #instances where the trust owner is delinquent in collecting from the trust
    prepEnvironment(accounts[1])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      console.log result
      console.log 'sending ether'
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      #console.log err
      #need to set the pay out for the example
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1, from: accounts[1])
    .then (result)->#call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 250000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      startBalance = web3.eth.getBalance(accounts[0])
      console.log 'Start Balance' + startBalance
      i.Withdraw(from: accounts[1])
    .then (result)->
      console.log result
      web3.eth.getBalance(i.address)
    .then (result)->
      console.log 'withdrawl:' + result
      assert.equal result.toNumber(), parseInt(web3.toWei(0.18,"ether")) - parseInt(web3.toWei(0.01,"ether")) * 0.005, 'withdraw wasnt right'
      web3.eth.getBalance(accounts[0])
    .then (result)->
      console.log result
      #since payout is 0 eth per usd we multiply fiatpayout 1
      #we only test .9 eth and 1.1 because gas costs weigh in
      # so much gas cost
      #96 413397700000000000
      #96 502336500000000000
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() > startBalance.toNumber(), true, 'eth didnt transfer'
      assert.equal result.toNumber() <= startBalance.toNumber() + parseInt(web3.toWei(0.01,"ether")), true, 'too much eth transfered'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      assert.equal result.toNumber(), 250000000000000000 + parseInt(web3.toWei(0.01,"ether")) * 0.005, 'Fee wasnt paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'
  it "does charge setup",  ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
      .then ->
        custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      startBalance = result
      i.StartTrust(from:accounts[0])
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      assert.equal parseInt(web3.toWei(0.25,"ether")), result.toNumber(), 'origination fee wasnt paid'
  it "wont start up if not enough ether",  ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.14,"ether") })
    .then (result)->
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
      .then ->
        custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      startBalance = result
      i.StartTrust(from:accounts[0])
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      assert.equal true, false, 'shouldnt be here'
    .catch (err)->
      if err.toString().indexOf("invalid op") > -1
        console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal err.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        #check that throw wasnt before this was correct
        assert.equal true, false, "odd err" + err
  it "only custodian owner can update custodian", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    foundOwner = null
    startCustodianBalance = 0
    custodian2 = null
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      prepEnvironment(accounts[4])
    .then (result)->
      console.log 'second evn up'
      custodian2 = result.custodian
      i.UpdateCustodian(custodian2.address, from:accounts[0])
    .then (result)->
      console.log 'custodian should be updated'
      i.custodian()
    .then (result)->
      console.log result
      console.log custodian2.address
      foundOwner = result
      assert.equal result, custodian2.address, 'custodian owner wasnt changed'
      console.log 'goign to try a bad update'
      i.UpdateCustodian(custodian.address, from:accounts[0])
    .then (result)->
      assert.equal false, true, 'shouldnt be here'
    .catch (err)->
      if err.toString().indexOf("invalid op") > -1
        console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal err.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
        assert.equal foundOwner, custodian2.address, 'custodian owner wasnt changed'
      else
        #check that throw wasnt before this was correct
        assert.equal true, false, "odd err" + err

  it "can transfer non native token", ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    franchiseeStartBalance = 0
    custodian = null
    nextPayout = 0
    token = null
    wantedTokenBalance = null
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(3.4,"ether") })
    .then (result)->
      #oops going to send tokens to a eth trust
      token.transfer(i.address, 5000, { from: accounts[0] })
    .then (result)->
      #need to be able to tranfer these tokens elewhere if owner
      i.TransferTokens(token.address, accounts[3], 2500, from: accounts[0])
    .then (result)->
      token.balanceOf(accounts[3])
    .then (result)->
      wantedTokenBalance = result.toNumber()
      assert.equal result.toNumber(), 2500, "tokens didn't transfer"
      i.TransferTokens(token.address, accounts[4], 1000, from: accounts[4])
    .then (result) ->
      token.balanceOf(accounts[4])
    .then (result) ->
      assert.equal result.toNumber(), 0, "tokens transfered that shouldn't"
    .catch (err)->
      if err.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal err.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
        assert.equal wantedTokenBalance, 2500, "tokens didn't transfer"
      else
        #check that throw wasnt before this was correct
        assert.equal true, false, "odd err" + err
  it "can transfer ether if not an ether trust", ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    franchiseeStartBalance = 0
    custodian = null
    nextPayout = 0
    token = null
    wantedTokenBalance = null
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      web3.eth.getBalance(accounts[3])
    .then (result)->
      startBalance = result
      console.log 'about to transfer tokens'
      #need to be able to tranfer these tokens elewhere if owner
      i.TransferTokens(ethTokenAddress, accounts[3],  web3.toWei(0.03,"ether"), from: accounts[0])
    .then (result)->
      console.log 'tokens transfered'
      web3.eth.getBalance(accounts[3])
    .then (result)->
      console.log result.toNumber()
      wantedTokenBalance = result.toNumber()
      i.TransferTokens(ethTokenAddress, accounts[4], web3.toWei(0.02,"ether"), from: accounts[4])
    .then (result)->
      assert.equal result.toNumber(), 0, "tokens transfered that shouldn't"
      token.balanceOf(accounts[4])
    .catch (err)->
      if err.toString().indexOf("invalid op") > -1
        console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal err.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
        assert.equal wantedTokenBalance - startBalance.toNumber(),  web3.toWei(0.03,"ether"), "tokens didn't transfer"
      else
        #check that throw wasnt before this was correct
        assert.equal true, false, "odd err" + err
  it "owner can set backup address", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    foundOwner = null
    startCustodianBalance = 0
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      i.UpdateBackup(accounts[4], from:accounts[1])
    .then (result)->
      i.backupOwner()
    .then (result)->
      foundOwner = result
      assert.equal result, accounts[4], 'backup owner wasnt set'
      i.UpdateBackup(accounts[5], from:accounts[0])
    .then (result)->
      assert.equal false, true, 'shouldnt be here'
    .catch (err)->
      if err.toString().indexOf("invalid op") > -1
        console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal err.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
        assert.equal foundOwner, accounts[4], 'backup owner wasnt set'
      else
        #check that throw wasnt before this was correct
        assert.equal true, false, "odd err" + err


  it "will give a liquidation conversion ratio if it has been five days since custodian published a conversion rate"

  it "should pay 10 percent to franchisee if different than custodian on token trust", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    franchiseeStartBalance = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1,"ether") })
    .then (result)->
      i.UpdateFranchisee(accounts[7], from: accounts[0])
    .then (result)->
      i.franchisee()
    .then (result)->
      assert.equal result, accounts[7], 'francisee wasnt set'
      i.StartTrust(from:accounts[0])
    .then (result)->
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      #console.log err
      token.balanceOf(accounts[0])

    .then (result)->
      startBalance = result
      console.log startBalance
      web3.eth.getBalance(accounts[7])
    .then (result)->
      console.log 'account 7 balance ' + result.toNumber()
      franchiseeStartBalance = result
      #need to set the pay out for the example
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
      .then ->
        custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 225000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      token.balanceOf(i.address)
    .then (result)->
      console.log result
      assert.equal result.toNumber(), (5000 - 2), 'withdraw wasnt right'
      token.balanceOf(accounts[0])
    .then (result)->
      console.log result
      #since payout is .1 eth per usd we multiply fiatpayout 1
      #we only test .9 eth and 1.1 because gas costs weigh in
      #96 413397700000000000
      #96 502336500000000000
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() == startBalance.toNumber() + 2, true, 'token didnt transfer'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid to custodian' + result
      assert.equal result.toNumber(), startCustodianBalance + parseInt(web3.toWei(0.4,"ether")) * 0.005 * 0.9, 'Fee wasnt paid'
      web3.eth.getBalance(accounts[7])
    .then (result)->
      console.log 'fee paid franchisee' + result
      assert.equal  result.toNumber() - franchiseeStartBalance.toNumber(), parseInt(web3.toWei(0.4,"ether")) * 0.005 * 0.1, 'Franchisee Fee wasnt paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'

  it "should allow withdraw after 1 month and ether goes to owner, fee is paid and so is franchisee",  ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    franchiseeStartBalance = 0
    custodian = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.UpdateFranchisee(accounts[7], from: accounts[0])
    .then (result)->
      i.franchisee()
    .then (result)->
      assert.equal result, accounts[7], 'francisee wasnt set'
      #need to set the pay out for the example
      custodian.SetConversion(ethTokenAddress, usdCurrencybytes, 1989, 1, 1, web3.toWei(0.01,"ether"),1)
    .then (result)->#call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
      i.StartTrust(from:accounts[0])

    .then (result)->
      console.log result
      console.log 'sending ether'
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->
      #console.log err
      startBalance = web3.eth.getBalance(accounts[0])
      console.log 'Start Balance' + startBalance
      web3.eth.getBalance(accounts[7])
    .then (result)->
      console.log 'account 7 balance ' + result.toNumber()
      franchiseeStartBalance = result

      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 225000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      console.log 'about to withdraw'
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      web3.eth.getBalance(i.address)
    .then (result)->
      console.log 'withdrawl:' + result
      assert.equal result.toNumber(), parseInt(web3.toWei(.18,"ether")) - parseInt(web3.toWei(0.01,"ether")) * 0.005, 'withdraw wasnt right'
      web3.eth.getBalance(accounts[0])
    .then (result)->
      console.log result
      #since payout is .1 eth per usd we multiply fiatpayout 1
      #we only test .2 eth and 1.1 because gas costs weigh in
      #96 413397700000000000
      #96 502336500000000000
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.00009,"ether")), true, 'eth didnt transfer'
      assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.01,"ether")), true, 'too much eth transfered'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      # .1fee plus 2.5 origination fee
      assert.equal result.toNumber(), (parseInt(web3.toWei(.01,"ether")) * 0.005 * 0.9) + parseInt(web3.toWei(0.225,"ether")), 'Fee wasnt paid'
      web3.eth.getBalance(accounts[7])
    .then (result)->
      console.log 'fee paid franchisee' + result
      #gas is spent in the transfer so the math doesn't work exatly right
      console.log result.toNumber() - franchiseeStartBalance.toNumber()
      console.log parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.1
      console.log result.toNumber() - franchiseeStartBalance.toNumber() <= parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.1
      assert.equal  result.toNumber() - franchiseeStartBalance.toNumber() <= parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.1, true, 'Franchisee Fee wasnt less than' + parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.1
      assert.equal  result.toNumber() - franchiseeStartBalance.toNumber() >= parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.09, true, 'Franchisee Fee wasnt greater than' + parseInt(web3.toWei(0.01,"ether")) * 0.005 * 0.11
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'

  it "should let custodian set franchisee", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      i.UpdateFranchisee(accounts[4], from:accounts[0])
    .then (result)->
      i.franchisee()
    .then (result)->
      assert.equal result, accounts[4], 'francisee wasnt set'
  it "should let owner set franchisee before active", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      i.UpdateFranchisee(accounts[4], from:accounts[1])
    .then (result)->
      i.franchisee()
    .then (result)->
      assert.equal result, accounts[4], 'francisee wasnt set'

  it "should not let random address set franchisee", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      i.UpdateFranchisee(accounts[4], from:accounts[7])
    .then (result)->
      assert.equal true,false, 'shouldnt be here'
    .then (result)->
      assert.equal result, "0x0000000000000000000000000000000000000000", 'francisee was set'
    .catch (error)->
      #console.log error
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
  it "should not let owner set franchisee after bActive goes to true", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[1]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      token.transfer(trustAddress, 5000 * 10**18, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })

    .then (result)->
      console.log('starting trust')
      i.StartTrust(from:accounts[1])
    .then (result)->
      i.UpdateFranchisee(accounts[7], from:accounts[1])
    .then (result)->
      assert.equal true, false, 'shouldnt be here'
    .then (result)->
      assert.equal result, "0x0000000000000000000000000000000000000000", 'francisee was set'
    .catch (error)->
      #console.log error
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())


  it "should limit fee to a max of 50", ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 20000, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000 * 10**18, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      console.log 'hello'
      i.owner()
    .then (result)->
      console.log 'owner info'
      console.log result
      console.log accounts[0]
      assert.equal result, accounts[0], "owner is not who you think it is"
      i.StartTrust(from:accounts[0])
    .then (result)->
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      #console.log err
      token.balanceOf(accounts[0])
    .then (result)->
      startBalance = result
      console.log startBalance
      #need to set the pay out for the example
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 10**18, 10000)
      .then ->
        custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),50)
    .then (result)->#call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 250000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      i.Withdraw(from: accounts[0])
    .then (result)->
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      #the ether to dollar ration is .01 to $50 so the fee should cap out at .1 ether
      assert.equal result.toNumber() - startCustodianBalance , parseInt(web3.toWei(0.01,"ether")), 'Fee wasnt paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'
  it "can initialize environment", ->
    i = null
    custodian = null
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (instance)->
      i = instance
  it "does set custodian properly", ->
    i = null
    custodian = null
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      i = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          i = FiatTrust.at(o.args.location)
      i.custodian()
    .then (result)->
      console.log custodian.address
      console.log result
      assert.equal result, custodian.address, 'wrong custodian'
  it "doesnt allow withdraw if period hasnt passed", ->
    i = null
    custodian = null
    prepEnvironment(accounts[0]).then (instance)->
      custodian = instance.custodian
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          i = FiatTrust.at(o.args.location)
      #console.log i
      console.log 'about to send'
      #console.log accounts[1]
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: 14000 })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->

      console.log result
      #try to withdraw without time passing
      console.log 'about to withdraw'
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log 'seemed to work'
      assert.equal false, true, 'withdraw didnt fail'
    .catch (error)->
      #console.log error
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
  it "should be on when it starts and has no ether", ->
    i = null
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          i = FiatTrust.at(o.args.location)
      #check if the bActive bit was inited
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      i.bActive()

    .then (result)->
      assert.equal result, true, 'contract was off before getting ether'
  it "custodian have a function Period that returns the length of a month", ->
    i = null
    custodian = null
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          i = FiatTrust.at(o.args.location)
      custodian.Period()
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), 2649600, 'Period Function doesnt work'

  it "should have a function NextWithdraw that returns the first withdraw time", ->
    i = null
    startTime = null
    contractA = null
    prepEnvironment(accounts[0])
    .then (instance)->

      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      #check that the contractStart i stored
      console.log "trust" + i.address
      #console.log i
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(.44,"ether") })
    .then ->
      i.StartTrust(from:accounts[0])
    .then (result)->
      i.currentTerm.call(from:accounts[0])
    .then (result)->
      console.log "result" + result
      i.contractStart(from:accounts[0])
    .then (result)->
      #console.log i
      console.log 'start ' + result
      startTime = result
      i.NextWithdraw.call(from:accounts[0])
    .then (result)->
      console.log result
      assert.equal result.toNumber(), startTime.toNumber() + 2649600, 'NextWithdraw doesnt work'
    .catch (err)->
      console.log 'found err'
      console.log err
  it "Can recieve Ether", ->
    i = null
    startBalance1 = 0
    endBalance1 = 0
    startBalance0 = 0
    endBalance0 = 0
    prepEnvironment(accounts[0])
    .then (instance)->

      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, from: accounts[0])
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      web3.eth.getBalance(accounts[1])
    .then (result)->
      startBalance1 = result
      web3.eth.getBalance(i.address)
    .then (result)->
      startBalance0 = result
      #Send some eth to the contract and make sure it moves
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      #console.log result
      web3.eth.getBalance(accounts[1])
    .then (result)->
      endBalance1 = result
      web3.eth.getBalance(i.address)
    .then (result)->
      endBalance0 = result
      #console.log startBalance0.toNumber()
      #console.log endBalance0.toNumber()
      #console.log startBalance1.toNumber()
      #console.log endBalance1.toNumber()
      #expect that the contract now has a balance
      assert.equal endBalance0.toNumber(), startBalance0.toNumber() + web3.toWei(0.44,"ether"), 'account 0 didnt update'
      #expect that account 1 burned some gas sending ether and has less balance
      assert.equal endBalance1.toNumber() < startBalance1.toNumber(), true, 'account 1 didnt update'

      i.StartTrust(from:accounts[0])
    .then (result)->
      i.bActive.call()
    .then (result)->
      assert.equal result, true, 'contract didnt turn on'
  it "should fail if constructor sent ether", ->
    i = null
    #this should fail because we are sending ether - doesnt have to be this way, we could make
    #constructor payable
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, {from: accounts[0], value: 1400})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
    .then (result)->
      assert.equal result, false, 'contract was on before getting ether'
    .catch (error)->
      assert.equal error.toString().indexOf("non-payable") > -1, true, 'didnt find non-payable error'

  it "should allow withdraw after 1 month and ether goes to owner, fee is paid",  ->
    i = null
    startBalance = 0
    startCustodianBalance = 0
    custodian = null
    nextPayout = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1, {from: accounts[0]})
    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      console.log result
      console.log 'sending ether'
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      #console.log err
      #need to set the pay out for the example
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->#call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
      console.log 'conversion set'
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      custodian.GetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date())
    .then (result)->
      console.log 'conversion' + result
      custodian.GetConversionByTimestamp(ethTokenAddress, usdCurrencybytes, nextPayout)
    .then (result)->
      console.log result
      console.log custodian.address
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 250000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      startBalance = web3.eth.getBalance(accounts[0])
      console.log 'Start Balance' + startBalance
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      web3.eth.getBalance(i.address)
    .then (result)->
      console.log 'withdrawl:' + result
      assert.equal result.toNumber(), parseInt(web3.toWei(0.18,"ether")) - parseInt(web3.toWei(0.01,"ether")) * 0.005, 'withdraw wasnt right'
      web3.eth.getBalance(accounts[0])
    .then (result)->
      console.log result
      #since payout is 0 eth per usd we multiply fiatpayout 1
      #we only test .9 eth and 1.1 because gas costs weigh in
      # so much gas cost
      #96 413397700000000000
      #96 502336500000000000
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() > startBalance.toNumber(), true, 'eth didnt transfer'
      assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.01,"ether")), true, 'too much eth transfered'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      assert.equal result.toNumber(), 250000000000000000 + parseInt(web3.toWei(0.01,"ether")) * 0.005, 'Fee wasnt paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'
  it "should allow withdraw after 1 month and token goes to owner, fee is paid",  ->
    i = null
    startBalance = 0
    custodian = null
    token = null
    nextPayout = 0
    startCustodianBalance = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #this function advances time in our test client by 34 days
      return new Promise (tResolve, tReject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          tResolve true
    .then (result)->
      #console.log err
      token.balanceOf(accounts[0])
    .then (result)->
      startBalance = result
      console.log startBalance
      #need to set the pay out for the example
      i.NextWithdraw()
    .then (result)->
      console.log 'next ' + result
      nextPayout = result.toNumber()
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
      custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
      .then ->
        custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.01,"ether"),1)
    .then (result)->#call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
      console.log 'conversion set'
      console.log result.logs[0].args
      aDate = nextPayout * 1000
      aDate = moment.utc(new Date(aDate))
      console.log aDate
      custodian.GetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date())
    .then (result)->
      console.log 'conversion' + result
      custodian.GetConversionByTimestamp(token.address, usdCurrencybytes, nextPayout)
    .then (result)->
      console.log result
      i.owner()
    .then (result)->
      console.log result
      console.log accounts[0]
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log result
      startCustodianBalance = result.toNumber()
      assert.equal 250000000000000000, startCustodianBalance, 'custodian has ether it shouldnt'
      i.Withdraw(from: accounts[0])
    .then (result)->
      console.log result
      token.balanceOf(i.address)
    .then (result)->
      console.log result
      assert.equal result.toNumber(), (5000 - 2), 'withdraw wasnt right'
      token.balanceOf(accounts[0])
    .then (result)->
      console.log result
      #since payout is .1 eth per usd we multiply fiatpayout 1
      #we only test .9 eth and 1.1 because gas costs weigh in
      #96 413397700000000000
      #96 502336500000000000
      #
      console.log 'eth increased' + (result.toNumber() - startBalance.toNumber())
      assert.equal result.toNumber() == startBalance.toNumber() + 2, true, 'token didnt transfer'
      web3.eth.getBalance(custodian.address)
    .then (result)->
      console.log 'fee paid' + result
      assert.equal result.toNumber(), 250000000000000000 + parseInt(web3.toWei(.4,"ether")) * 0.005, 'Fee wasnt paid'
    .catch (err)->
      console.log err
      assert.equal false, true, 'an error occured'

  it "should not allow more than term number of withdraws",->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawFunction = ()->
      return q.Promise (resolve, reject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
            .then ->
              custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.1,"ether"),1)
          .then (result) ->
            i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.88,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      #make 13 withdraws and the last one should fail
      async.eachSeries [1..13], (item, done)->
        #console.log item
        withdrawFunction()
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          currentTerm = result
          console.log 'term ' + result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      assert(false, "shouldnt be here")
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal 13, currentTerm.toNumber(), "current term wasnt 12"
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())

  it "should not allow withdraw if some time has passed, but not enough", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    #this function takes a thisTerm and nullifies the time passage if after 3
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 4
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
            .then ->
              custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.1,"ether"),1)
          .then (result) ->
            i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.44,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      #after the 3rd withdraw we stop advancing time and expect a throw
      async.eachSeries [1..11], (item, done)->
        #console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          currentTerm = result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      assert(false, "shouldnt be here")
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal currentTerm.toNumber(), 4
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())

  it "should allow withdraw all after term is over for tokens", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawcount = 0
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(token.address, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 1,20)
            .then ->
              custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), web3.toWei(0.1,"ether"),1)
          .then (result) ->
            i.Withdraw(from: accounts[0])
          .then (result)->
            withdrawcount = withdrawcount + 1
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(token.address, usdCurrencybytes, 12, 40, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      token.transfer(trustAddress, 5000, { from: accounts[0] })
    .then (result)->
      console.log result
      console.log 'sending ether'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.88,"ether") })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      async.eachSeries [1..12], (item, done)->
        console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          currentTerm = result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #should be 4976 eth left in the contract
      token.balanceOf(i.address)
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), 4976, "contract had less than expected"
      token.balanceOf(accounts[0])
    .then (result)->
      startBalance = result
      #console.log 'calling withdrawall'
      #try to withdraw the remaining .2 ETH
      i.CloseTrust(accounts[0], from:accounts[0])
    .then (result)->
      assert.equal withdrawcount, 12, "didnt withdraw enough"
      #console.log 'checking balance'
      token.balanceOf(i.address)
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), 0, "contract had more than expected"
      #web3.eth.getBalance(accounts[0])
      token.balanceOf(accounts[0])
    .then (result)->
      #console.log result
      #assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.19, "ether")), true, "not enough withdrawn"
      #assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.21, "ether")), true, "too much withdrawn"
      assert.equal result.toNumber(), tokenStartBalance, "too much withdrawn"



    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, false, 'found an op throw'
      else
        assert(false, error.toString())

  it "should allow withdraw all after term is over for ether", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 10**18,1000)
          .then (result) ->
            i.term()
          .then (result) ->
            console.log result
            i.currentTerm()
          .then (result) ->
            console.log result
            console.log 'about to withdraw'
            i.Withdraw(from: accounts[0])
          .then (result)->
            console.log 'withdrawn'
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 100, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: 10 * (10**18) })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'
      async.eachSeries [1..12], (item, done)->
        #console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          currentTerm = result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #should be 4976 eth left in the contract
      web3.eth.getBalance(i.address)
    .then (result)->
      #console.log result
      #- (25* (10**16 handles the fee paid to start the trust
      assert.equal result.toNumber(), parseInt(web3.toWei(8.8, 'ether')) - parseInt(web3.toWei(0.006, 'ether')) - (25 * (10**16)), "contract had less than expected"
      web3.eth.getBalance(accounts[0])
    .then (result)->
      startBalance = result
      #console.log 'calling withdrawall'
      #try to withdraw the remaining .2 ETH
      console.log 'closing'
      i.CloseTrust(accounts[0], from:accounts[0])
    .then (result)->
      #console.log 'checking balance'
      web3.eth.getBalance(i.address)
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), 0, "contract had more than expected"
      #web3.eth.getBalance(accounts[0])
      web3.eth.getBalance(accounts[0])
    .then (result)->
      #console.log result
      assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(8.7, "ether")) - (25 * (10**16)), true, "not enough withdrawn"
      assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(8.9, "ether")) - (25 * (10**16)), true, "too much withdrawn"
      #assert.equal result.toNumber(), 100000, "too much withdrawn"

    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, false, 'found an op throw'
      else
        assert(false, error.toString())




  it "should reduce payout if not enough ether for full term", ->
    i = null
    lastTerm = 0
    startBalance = 0
    custodian = null
    currentTerm = 0
    token = null
    withdrawFunction = (thisTerm)->
      return q.Promise (resolve, reject)->
        timeFudge = 0
        if thisTerm < 15
          timeFudge = 1
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34 * timeFudge],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.NextWithdraw()
          .then (result)->
            console.log 'next ' + result
            nextPayout = result.toNumber()
            aDate = nextPayout * 1000
            aDate = moment.utc(new Date(aDate))
            console.log aDate
            console.log 'conversion set for ' + aDate.year() + (aDate.month() + 1) + aDate.date()
            custodian.SetConversion(ethTokenAddress, usdCurrencybytes, aDate.year(), aDate.month() + 1, aDate.date(), 10**18,1000)
          .then (result) ->
            i.term()
          .then (result) ->
            console.log result
            i.currentTerm()
          .then (result) ->
            console.log result
            console.log 'about to withdraw'
            i.Withdraw(from: accounts[0])
          .then (result)->
            console.log 'withdrawn'
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    prepEnvironment(accounts[0])
    .then (instance)->
      custodian = instance.custodian
      token = instance.token
      console.log "custodian:" + custodian.address
      custodian.CreateTrust(ethTokenAddress, usdCurrencybytes, 12, 1000, {from: accounts[0]})

    .then (txn)->
      trustAddress = null
      txn.logs.map (o)->
        if o.event is 'TrustCreated'
          console.log 'found new Trust at' + o.args.location
          i = FiatTrust.at(o.args.location)
          trustAddress = o.args.location
      console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: 2 * (10**18) })
    .then (result)->
      i.StartTrust(from:accounts[0])
    .then (result)->
      #console.log result
      #console.log 'sending'

      #console.log item
      withdrawFunction(1)
      .then (result)->
        i.currentTerm.call(from: accounts[0])
    .then (result)->
      #should be 4976 eth left in the contract
      web3.eth.getBalance(i.address)
    .then (result)->
      console.log result
      #- (25* (10**16 handles the fee paid to start the trust
      assert.equal result.toNumber(), 1608462500000000000, "contract had less than expected"
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, false, 'found an op throw'
      else
        assert(false, error.toString())
