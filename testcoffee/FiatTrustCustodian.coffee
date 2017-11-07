FiatTrustCustodian = artifacts.require('./FiatTrustCustodian.sol')
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
    FiatTrustCustodian.new(from: custodianOwner).then (instance)->
      custodian = instance
      FiatTrustFactory.new(custodian.address, from: custodianOwner)
    .then (instance)->
      console.log 'new factory'
      factory = instance
      DateTime.new(from: custodianOwner)
    .then (instance)->
      console.log 'new DateTime'
      custodian.SetDateTimeLibrary(instance.address, from: custodianOwner)
    .then (result)->
      console.log 'dt set'
      custodian.SetFactory(factory.address, from:custodianOwner)
    .then (result)->
      console.log 'factory set'
      HumanStandardToken.new(tokenStartBalance,"token",0,'tkn', from: custodianOwner)
    .then (instance)->
      console.log 'new token'
      token = instance
      TokenStorage.new(from: custodianOwner)
    .then (instance)->
      console.log 'new storage'
      storage = instance
      custodian.SetStorage(storage.address, from: custodianOwner)
    .then (instance)->
      storage.UpdateOwner(custodian.address, true, from: custodianOwner)

    .then ->
      resolve
        custodian: custodian
        token: token

contract 'FiatTrustCustodian', (paccounts)->
  accounts = paccounts
  console.log accounts

  it "should allow toggleing of owner", ->
    i = null
    initialOwner = null
    nextOwner = null
    FiatTrustCustodian.new(from: accounts[0]).then (instance)->
      i = instance
      #console.log i
      #check the current owner
      i.owner()
    .then (result)->
      #console.log result
      initialOwner = result

    .then (result)->
      i.TransferOwnership(accounts[1], from: accounts[0])
    .then (txn)->
      i.owner()
    .then (result)->
      #account 0 should still be an owner
      #console.log result
      nextOwner = result
      i.TransferOwnership(accounts[2], from: accounts[0])#should fail
    .then ->
      assert(false, 'shouldnt be here')
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
      return true
    .then ->
      assert.equal initialOwner, accounts[0], 'initial owner was wrong'
      assert.equal nextOwner, accounts[1], 'next owner was wrong'
  it "should allow setting of dateTimeLibrary", ->
    i = null
    initialOwner = null
    nextOwner = null
    FiatTrustCustodian.new(from: accounts[0]).then (instance)->
      i = instance
      #console.log i
      #check the current owner
      i.SetDateTimeLibrary(accounts[4])
    .then (result)->
      i.dateTimeLibrary()
    .then (result)->
      console.log 'datetime library is' + result
      assert result, accounts[4], 'library wasnt set'
  it "should have a function Period that returns the length of a month", ->
    i = null
    FiatTrustCustodian.new(from: accounts[0]).then (instance)->
      i = instance
      #check calculation
      i.Period()
    .then (result)->
      console.log 'period' + result
      assert.equal result.toNumber(), 2649600, 'Period Function doesnt work'
  it "can set conversion for token/currency/date tripple and retrieve by timestamp", ->
    i = null
    testTimestamp = ((new Date('1/1/2017')).getTime() / 1000 )
    prepEnvironment(accounts[0]).then (instance)->
      i = instance.custodian
      i.BuildDateSig(ethTokenAddress, usdCurrencybytes, 2017, 1, 1)
    .then (result)->
      console.log 'by ints ' + result
      console.log testTimestamp
      i.BuildDateSigByTimestamp(ethTokenAddress, usdCurrencybytes, testTimestamp)
    .then (result)->
      console.log 'by ts ' + result
      i.SetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 1, 20, 1, from: accounts[0])
    .then (result)->
      i.GetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 1)
    .then (result)->
      assert.equal result.toNumber(), (20 * 10**18), "item wasnt written"
      console.log testTimestamp
      i.GetConversionByTimestamp(ethTokenAddress, usdCurrencybytes, testTimestamp)
    .then (result)->
      assert.equal result.toNumber(), (20 * 10**18), "item wasnt retrievable by timestamp"
  it 'does report most recent price', ->
    i = null
    testTimestamp = ((new Date('1/1/2017')).getTime() / 1000 )
    prepEnvironment(accounts[0]).then (instance)->
      i = instance.custodian

      i.BuildDateSig(ethTokenAddress, usdCurrencybytes, 2017, 1, 1)
    .then (result)->
      console.log 'by ints ' + result
      console.log testTimestamp
      i.BuildDateSigByTimestamp(ethTokenAddress, usdCurrencybytes, testTimestamp)
    #note dates are submitted out of order.  We don't want a correction to reported as the most recent
    .then (result)->
      console.log 'by ts ' + result
      i.SetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 1, 20, 1, from: accounts[0])
    .then (result)->
      console.log 'by ts ' + result
      i.SetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 2, 30, 1, from: accounts[0])
    .then (result)->
      console.log 'by ts ' + result
      i.SetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 5, 50, 1, from: accounts[0])
    .then (result)->
      console.log 'by ts ' + result
      i.SetConversion(ethTokenAddress, usdCurrencybytes, 2017, 1, 3, 40, 1, from: accounts[0])
    #.then (result)->
    #  i.GetTokenCurrencyPair(ethTokenAddress,usdCurrencybytes)
    .then (result)->
      i.getMaxConversionDate(ethTokenAddress, usdCurrencybytes)
    .then (result)->
      aDate = result * 1000
      aDate = moment.utc(new Date(aDate))

      assert.equal aDate.year(), 2017, "year isnt being recorded"
      assert.equal aDate.month() + 1, 1, "month isnt being recorded"
      assert.equal aDate.date(), 5, "day isnt being recorded"
  ###
  it 'can withdraw sent funds'
  it 'will fail to create token trust if token is not whitelisted'
  it 'can whitelist a token'
  it 'does charge a setup fee'
  it "should be off when it starts and has no ether", ->
    i = null
    DisciplineWallet.new(12,1000, from: accounts[0]).then (instance)->
      i = instance
      #check if the bActive bit was inited
      i.bActive.call()
    .then (result)->
      assert.equal result, false, 'contract was on before getting ether'
  it "should have a function Period that returns the length of a month", ->
    i = null
    DisciplineWallet.new(12,1000, from: accounts[0]).then (instance)->
      i = instance
      #check calculation
      i.Period.call()
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), 2649600, 'Period Function doesnt work'
  it "should have a function NextWithdraw that returns the first withdraw time", ->
    i = null
    startTime = null
    DisciplineWallet.new(12,1000, from: accounts[0]).then (instance)->
      i = instance
      #check that the contractStart is tored
      i.contractStart.call()
    .then (result)->
      startTime = result
      #check that the next withdraw calc works
      i.NextWithdraw.call()
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), startTime.toNumber() + 2649600, 'NextWithdraw doesnt work'
  it "should turn on when sent ether", ->
    i = null
    startBalance1 = 0
    endBalance1 = 0
    startBalance0 = 0
    endBalance0 = 0
    DisciplineWallet.new(12,1000, from: accounts[0]).then (instance)->
      i = instance
      web3.eth.getBalance(accounts[1])
    .then (result)->
      startBalance1 = result
      web3.eth.getBalance(i.address)
    .then (result)->
      startBalance0 = result
      #Send some eth to the contract and make sure it moves
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: 14000 })
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
      assert.equal endBalance0.toNumber(), startBalance0.toNumber() + 14000, 'account 0 didnt update'
      #expect that account 1 burned some gas sending ether and has less balance
      assert.equal endBalance1.toNumber() < startBalance1.toNumber(), true, 'account 1 didnt update'
      i.bActive.call()
    .then (result)->
      assert.equal result, true, 'contract didnt turn on'
  it "should fail if constructor sent ether", ->
    i = null
    #this should fail because we are sending ether - doesnt have to be this way, we could make
    #constructor payable
    DisciplineWallet.new(12, 1000, {from: accounts[0], value: 14000}).then (instance)->
      i = instance
      i.bActive.call()
    .then (result)->
      assert.equal result, false, 'contract was on before getting ether'
    .catch (error)->
      assert.equal error.toString().indexOf("non-payable") > -1, true, 'didnt find non-payable error'
  it "should allow withdraw after 1 month and ether goes to owner",  (done)->
    i = null
    startBalance = 0
    #console.log 'starting'
    #we want a wallet that pays out over 12 months at 0.1 ether per month
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      #fund the wallet
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      #this function advances time in our test client by 34 days
      web3.currentProvider.sendAsync
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [86400 * 34],  # 86400 seconds in a day
        id: new Date().getTime()
      , (err)->
        #console.log err
        startBalance = web3.eth.getBalance(accounts[0])
        #console.log startBalance
        #call the withdraw fucntion.  0.1 eth shold move from the contract to account[0]
        i.Withdraw(from: accounts[0])
        .then (result)->
          web3.eth.getBalance(i.address)
        .then (result)->
          assert.equal result.toNumber(), web3.toWei(1.3,"ether"), 'withdraw wasnt right'
          web3.eth.getBalance(accounts[0])
        .then (result)->
          #console.log result
          #we only test .9 eth and 1.1 because gas costs weigh in
          assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.09,"ether")), true, 'eth didnt transfer'
          assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.1,"ether")), true, 'too much eth transfered'
          done()
    return

  it "should fail on instant withdrawl", ->
    i = null
    DisciplineWallet.new(12, 1000, from: accounts[0]).then (instance)->
      i = instance
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: 14000 })
    .then (result)->
      #try to withdraw without time passing
      i.Withdraw(from: accounts[0])
    .then (result)->
      assert.equal false, true, 'withdraw didnt fail'
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
      #done()
  it "should not allow more than term number of withdraws", (done)->
    i = null
    startBalance = 0
    withdrawFunction = ()->
      return q.Promise (resolve, reject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
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
          #console.log result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      assert(false, "shouldnt be here")
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
      done()

    return
  it "should not allow withdraw if some time has passed, but not enough", (done)->
    i = null
    startBalance = 0
    #this function takes a thisTerm and nullifies the time passage if after 3
    withdrawFunction = (thisTerm) ->
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
          i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
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
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      assert(false, "shouldnt be here")
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
      done()

    return
  it "should allow withdraw all after term is over", (done)->
    i = null
    startBalance = 0
    withdrawFunction = ()->
      return q.Promise (resolve, reject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.Withdraw(from: accounts[0])
          .then (result)->
            web3.eth.getBalance(i.address)
          .then (result)->
            #console.log result
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      #pass 12 terms
      async.eachSeries [1..12], (item, done)->
        #console.log item
        withdrawFunction()
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #should be .2 eth left in the contract
      web3.eth.getBalance(i.address)
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), parseInt(web3.toWei(0.2, "ether")), "contract had less than expected"
      web3.eth.getBalance(accounts[0])
    .then (result)->
      startBalance = result
      #console.log 'calling withdrawall'
      #try to withdraw the remaining .2 ETH
      i.WithdrawAll(accounts[0], from:accounts[0])
    .then (result)->
      #console.log 'checking balance'
      web3.eth.getBalance(i.address)
    .then (result)->
      #console.log result
      assert.equal result.toNumber(), parseInt(web3.toWei(0.0, "ether")), "contract had more than expected"
      web3.eth.getBalance(accounts[0])
    .then (result)->
      #console.log result
      assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.19, "ether")), true, "not enough withdrawn"
      assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.21, "ether")), true, "too much withdrawn"
      done()
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, false, 'found an op throw'
      else
        assert(false, error.toString())
      done()

    return
  it "should fail if withdrawAll is called before term is over", (done)->
    i = null
    startBalance = 0
    withdrawFunction = (thisTerm) ->
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
          i.Withdraw(from: accounts[0])
          .then (result)->
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      #do 3 withdraws
      async.eachSeries [1..3], (item, done)->
        #console.log item
        withdrawFunction(item)
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #try to withdrawAll and it should fail
      i.WithdrawAll(accounts[0], from:accounts[0])
    .then ->
      assert(false, 'shouldnt be here')
      done()
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'didnt find invalid op throw'
      else
        assert(false, error.toString())
      done()
    return
  it "should reject payment if payout term is expired", (done)->
    i = null
    startBalance = 0
    withdrawFunction = ()->
      return q.Promise (resolve, reject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.Withdraw(from: accounts[0])
          .then (result)->
            web3.eth.getBalance(i.address)
          .then (result)->
            #console.log result
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      #take out all 12 withdraws
      async.eachSeries [1..12], (item, done)->
        #console.log item
        withdrawFunction()
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #should sending a transaction to the account with more ether should fail if the term has passed
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      assert(false, "shouldnt be here")
      done()
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        assert(false, error.toString())
      done()
    return
  it "should deposit using deposit function", (done)->
    i = null
    startBalance = 0
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      i.Deposit({ from: accounts[1],value:web3.toWei(1.4,"ether")})
    .then (result)->
      web3.eth.getBalance(i.address)
    .then (result)->
      assert.equal result.toNumber(), parseInt(web3.toWei(1.4,"ether")), "deposit didnt work"
      done()
    return
  it "should allow for transfer of owner", (done)->
    i = null
    startBalance = 0
    endBalance = 0
    withdrawFunction = (fromAddress)->
      return q.Promise (resolve, reject)->
        web3.currentProvider.sendAsync
          jsonrpc: "2.0",
          method: "evm_increaseTime",
          params: [86400 * 34],  # 86400 seconds in a day
          id: new Date().getTime()
        , (err)->
          i.Withdraw(from: fromAddress)
          .then (result)->
            web3.eth.getBalance(i.address)
          .then (result)->
            #console.log result
            resolve result
          .catch (err)->
            reject err
    #console.log 'starting'
    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(1.4,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      async.eachSeries [1..4], (item, done)->
        #console.log item
        withdrawFunction(accounts[0])
        .then (result)->
          i.currentTerm.call(from: accounts[0])
        .then (result)->
          #console.log result
          done()
        .catch (err)->
          #console.log err
          done(err)
    .then (result)->
      #transfer the account to account 2
      i.transferOwnership(accounts[2], from: accounts[0])
    .then (result)->
      i.owner.call()
    .then (result)->
      #console.log result
      assert.equal accounts[2],result, "new owner wasnt set"
    .then (result)->
      startBalance = web3.eth.getBalance(accounts[2])
      #try to take the money out as the new owner should work
      withdrawFunction(accounts[2])
    .then (result)->
      endBalance = web3.eth.getBalance(accounts[2])
      assert.equal endBalance.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.09, "ether")), true, "not enough withdrawn"
      assert.equal endBalance.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.1, "ether")), true, "too much withdrawn"
      #now try to withdraw as original owner and should throw
      withdrawFunction(accounts[0])
    .then ->
      assert(false, 'shouldnt be here')
      done()
    .catch (error)->
      if error.toString().indexOf("invalid op") > -1
        #console.log("We were expecting a Solidity throw (aka an invalid op), we got one. Test succeeded.")
        assert.equal error.toString().indexOf("invalid op") > -1, true, 'found an op throw'
      else
        assert(false, error.toString())
      done()
    return
  it "should reduce payout if payout would drain account before the end of the term",  (done)->
    i = null
    startBalance = 0
    #console.log 'starting'

    DisciplineWallet.new(12, web3.toWei(0.1,"ether"), from: accounts[0]).then (instance)->
      i = instance
      #console.log 'have instance'
      web3.eth.sendTransaction({ from: accounts[1], to: i.address, value: web3.toWei(0.6,"ether") })
    .then (result)->
      #console.log result
      #console.log 'sending'
      web3.currentProvider.sendAsync
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [86400 * 34],  # 86400 seconds in a day
        id: new Date().getTime()
      , (err)->
        #console.log err
        startBalance = web3.eth.getBalance(accounts[0])
        #console.log startBalance
        i.Withdraw(from: accounts[0])
        .then (result)->
          web3.eth.getBalance(i.address)
        .then (result)->
          console.log result
          assert.equal result.toNumber(), web3.toWei(0.55, "ether"), 'withdraw wasnt right'
          web3.eth.getBalance(accounts[0])
        .then (result)->
          #console.log result
          #we only test .9 eth and 1.1 because gas costs weigh in
          assert.equal result.toNumber() > startBalance.toNumber() + parseInt(web3.toWei(0.04,"ether")), true, 'eth didnt transfer'
          assert.equal result.toNumber() < startBalance.toNumber() + parseInt(web3.toWei(0.5,"ether")), true, 'too much eth transfered'
          done()
    return
    ###


