const { assert, expect } = require("chai");
const { developmentChains } = require("../hardhat-config-helper");
const { network, deployments, ethers, getNamedAccounts } = require("hardhat");

!developmentChains.includes(network.name)
    ? describe.skip
    : describe("MultiSignWallet", function () {
          let MultiSignWallet;
          let deployer;
          let user1;
          let user2;
          let user3;
          const sendValue = ethers.parseEther("0.1");
          beforeEach(async () => {
              deployer = (await getNamedAccounts()).deployer;
              user1 = (await getNamedAccounts()).user1;
              user2 = (await getNamedAccounts()).user2;
              user3 = (await getNamedAccounts()).user3;
              await deployments.fixture(["all"]);
              MultiSignWallet = await ethers.getContract("MultiSignWallet", deployer);
              MultiSignWallet2 = await ethers.getContract("MultiSignWallet", user1);
              MultiSignWallet3 = await ethers.getContract("MultiSignWallet", user2);

          });

          describe("constructor", function () {
              it("Test if the MultiSignWallet all address correctly", async () => {
                  const ret = await MultiSignWallet.getOwners();
                  assert.equal(ret[0], deployer);
                  assert.equal(ret[1], user1);
                  assert.equal(ret[2], user2);

                });
          });

          describe("InitialTransactionCount", function () {
              it("Test InitialTransactionCount", async () => {
                  const ret = await MultiSignWallet.getTransactionCount();
                  assert.equal(ret,0);
              });
          });

          describe("submitTransaction", function () {
            it("Test submitTransaction", async () => {
                await MultiSignWallet.submitTransaction(deployer,sendValue);
                const ret = await MultiSignWallet.getTransactionCount();
                assert.equal(ret,1);
            });
        });

      });
