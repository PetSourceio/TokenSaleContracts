import ether from 'zeppelin-solidity/test/helpers/ether';
import { advanceBlock } from 'zeppelin-solidity/test/helpers/advanceToBlock';
import { increaseTimeTo, duration } from 'zeppelin-solidity/test/helpers/increaseTime';
import latestTime from 'zeppelin-solidity/test/helpers/latestTime';
import EVMRevert from 'zeppelin-solidity/test/helpers/EVMRevert';

const BigNumber = web3.BigNumber;

const should = require('chai')
  .use(require('chai-as-promised'))
  .use(require('chai-bignumber')(BigNumber))
  .should();

const Token = artifacts.require("./Token")
const TokenCrowdsale = artifacts.require("./TokenCrowdsale");
const TeamTokenHolder = artifacts.require("./TeamTokenHolder");

contract('CrowdsaleTest', function (accounts) {
  let investor = accounts[0];
  let wallet = accounts[1];
  let purchaser = accounts[2];
  let platform = accounts[3];
  let notWhitelistedInvestor = accounts[4];
  let advisor = accounts[5];
  let founder = accounts[6];
  let investorForShareHolders = accounts[7];

  let shareholdersPercentages = [50, 8, 4, 13];
  let rates = [12500, 11500, 11000, 10500, 10000];
  let icoCap = 200e24;
  let minPurchase = 100e18;
  let icoPercentage = 25;
  let phaseLength = 7;

  beforeEach(async function () {
    this.openingTime = latestTime() + duration.weeks(1);
    this.closingTime = this.openingTime + duration.weeks(1);
    this.token = await Token.new();

    this.crowdsale = await TokenCrowdsale.new(rates, wallet, this.token.address,
    phaseLength, icoCap, minPurchase, icoPercentage, this.openingTime);
    await this.crowdsale.addToWhitelist(investor);
    await this.crowdsale.addToWhitelist(purchaser);
    await this.token.transferOwnership(this.crowdsale.address);

    this.teamTokenHolder = await TeamTokenHolder.new(wallet, this.crowdsale.address, this.token.address);
    this.advisorTokenHolder = await TeamTokenHolder.new(advisor, this.crowdsale.address, this.token.address);
    this.founderTokenHolder = await TeamTokenHolder.new(founder, this.crowdsale.address, this.token.address);

    this.shareHoldersWallets = [platform, this.teamTokenHolder.address, this.advisorTokenHolder.address, this.founderTokenHolder.address];
  });

  describe('check initial setup', function() {
    it('should set closing time correctly', async function() {
      let expectedClosingTime = this.openingTime + duration.weeks(rates.length);
      let contractClosingTime = await this.crowdsale.closingTime();
      contractClosingTime.should.be.bignumber.equal(expectedClosingTime);
    });
    it('should set initial and closing rates correctly', async function() {
      let initialRate = await this.crowdsale.initialRate();
      initialRate.should.be.bignumber.equal(rates[0]);
      let finalRate = await this.crowdsale.finalRate();
      finalRate.should.be.bignumber.equal(rates[rates.length - 1]);
    });
  });
  describe('accepting payments', function () {
    it('should not accept payments before start date', async function () {
     await increaseTimeTo(latestTime());
     await this.crowdsale.send(ether(1)).should.be.rejectedWith(EVMRevert);
    });
    it('should not accept payments after end date', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length+5));
      await this.crowdsale.send(ether(1)).should.be.rejectedWith(EVMRevert);
    });
    it('should accept payments during ico time only when whitelisted', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await this.crowdsale.buyTokens(notWhitelistedInvestor, { value: ether(1) }).should.be.rejectedWith(EVMRevert);
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
    });
    it('should fail when sending 0 ethers', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await this.crowdsale.send(ether(0)).should.be.rejectedWith(EVMRevert);
    });
    it('should not allow buy less than 100 tokens', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await this.crowdsale.buyTokens(investor, { value: 1 }).should.be.rejectedWith(EVMRevert);
    });
  });

  describe('changing phases on date change', function () {
    it('should reveive correct amount of tokens when sending 1 ether for the 1\'st phase', async function () {
      await increaseTimeTo(this.openingTime + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
      const balance = await this.token.balanceOf(investor);
      balance.should.be.bignumber.equal(rates[0] * 1e18);
    });
    it('should reveive correct amount of tokens when sending 1 ether for the 2\'nd phase', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1) + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
      const balance = await this.token.balanceOf(investor);
      balance.should.be.bignumber.equal(rates[1] * 1e18);
    });
    it('should reveive correct amount of tokens when sending 1 ether for the 3\'rd phase', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(2) + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
      const balance = await this.token.balanceOf(investor);
      balance.should.be.bignumber.equal(rates[2] * 1e18);
    });
    it('should reveive correct amount of tokens when sending 1 ether for the 4\'th phase', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(3) + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
      const balance = await this.token.balanceOf(investor);
      balance.should.be.bignumber.equal(rates[3] * 1e18);
    });
    it('should reveive correct amount of tokens when sending 1 ether for the 5\'th phase', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(4) + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.fulfilled;
      const balance = await this.token.balanceOf(investor);
      balance.should.be.bignumber.equal(rates[4] * 1e18);
    });

    it('should reject when all tokens bought', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1) + duration.days(1));
      await this.crowdsale.buyTokens(investor, { value: ether(60000) }).should.be.fulfilled;
      await this.crowdsale.buyTokens(investor, { value: ether(1) }).should.be.rejectedWith(EVMRevert);
    });
  });

  describe('receive funds', function () {
    it('should forward funds to wallet when purchasing tokens', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1) + duration.days(1));
      const pre = await web3.eth.getBalance(wallet);
      await this.crowdsale.buyTokens(investor, { value: ether(10) }).should.be.fulfilled;
      const post = await web3.eth.getBalance(wallet);
      post.minus(pre).should.be.bignumber.equal(ether(10));
    });
    it('should set return funds if tokens are over', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1) + duration.days(1));
      const walletPre = await web3.eth.getBalance(wallet);
      const investorPre = await web3.eth.getBalance(investor);
      await this.crowdsale.buyTokens(investor, { value: ether(700000) });
      const walletPost = await web3.eth.getBalance(wallet);
      const investorPost = await web3.eth.getBalance(investor);
      const walletDiff = walletPost.minus(walletPre);
      const investorDiff = investorPre.minus(investorPost);
      // minor diff apears because of gas, so ranges should be used
      investorDiff.should.be.bignumber.gt(walletDiff.minus(ether(0.5)));
      investorDiff.should.be.bignumber.lt(walletDiff.plus(ether(0.5)));
    });
    it('should add wei to weiRaised when tokens are purchased', async function() {
      await increaseTimeTo(this.openingTime + duration.weeks(1) + duration.days(1));
      const pre = await web3.eth.getBalance(wallet);
      await this.crowdsale.buyTokens(investor, { value: ether(15000) });
      const weiRaised = await this.crowdsale.weiRaised();
      weiRaised.should.be.bignumber.equal(ether(15000));
    });
  });

  describe('finalize', function () {
    it('should not allow finalize when shareholders are not set', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.finalize().should.be.rejectedWith(EVMRevert);
    });
    it('should not allow finalize when not final dated reached or all tokens sold', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.rejectedWith(EVMRevert);
    });
    it('should allow finalize when final date is expired', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
    });
    it('should allow finalize when all tokens are sold', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await this.crowdsale.buyTokens(purchaser, { value: ether(70000) });
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
    });
    it('should transfer ownership when finallized', async function () {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
      const owner = await this.token.owner();
      owner.should.be.equal(wallet);
    });
    it('should assign correct amount of tokens to shareholders when all tokens are sold', async function () {
      // has its own setup
      let token = await Token.new();
      //mint all pre-ico
      await token.mint(wallet, 50e24);
      let crowdsale = await TokenCrowdsale.new(rates, wallet, token.address,
      phaseLength, icoCap, minPurchase, icoPercentage, this.openingTime);
      await crowdsale.addToWhitelist(investorForShareHolders);
      await token.transferOwnership(crowdsale.address);


      await increaseTimeTo(this.openingTime + duration.weeks(1));
      await crowdsale.buyTokens(investorForShareHolders, { value: ether(70000) });
      await crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await crowdsale.finalize().should.be.fulfilled;
      const walletBalance = await token.balanceOf(wallet);
      walletBalance.should.be.bignumber.equal(50e24);
      const teamTokenHolderBalance = await token.balanceOf(this.teamTokenHolder.address);
      teamTokenHolderBalance.should.be.bignumber.equal(80e24);
      const platformBalance = await token.balanceOf(platform);
      platformBalance.should.be.bignumber.equal(500e24);
      const advisorBalance = await token.balanceOf(advisor);
      advisorBalance.should.be.bignumber.equal(40e24);
      const founderBalance = await token.balanceOf(founder);
      platformBalance.should.be.bignumber.equal(130e24);
    });
    it('should finish minting when finalized', async function() {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
      let mintingFinished = await this.token.mintingFinished();
      mintingFinished.should.be.equal(true);
    });
    it('should burn all leftovers when finallized', async function() {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
      // nothing sold - everything gets burned
      let totalSupply = await this.token.totalSupply();
      totalSupply.should.be.bignumber.equal(0);
    });
   it('should set finalized time when finalized', async function() {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
      let finalizedTime = await this.crowdsale.finalizedTime();
      finalizedTime.should.be.bignumber.equal(this.openingTime + duration.weeks(rates.length + 4));
    });
    it('should not allow finalize when finalized', async function() {
      await increaseTimeTo(this.openingTime + duration.weeks(rates.length + 4));
      await this.crowdsale.setShareHolders(shareholdersPercentages, this.shareHoldersWallets);
      await this.crowdsale.finalize().should.be.fulfilled;
      await this.crowdsale.finalize().should.be.rejectedWith(EVMRevert);
    });
  });
});
