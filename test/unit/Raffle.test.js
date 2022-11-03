const { networkConfig, developmentChains } = require("../../helper-hardhat-config")
const { network, ethers, getNamedAccounts, deployments } = require("hardhat")
const { assert, expect } = require("chai")

!developmentChains.includes(network.name)
    ? describe.skip
    : describe("Raffle uint test", () => {
          let raffle, vrfCoordinatorV2Mock, deployer, entranceFee, interval

          beforeEach(async () => {
              deployer = (await getNamedAccounts()).deployer

              await deployments.fixture("all")

              raffle = await ethers.getContract("Raffle", deployer)

              vrfCoordinatorV2Mock = await ethers.getContract("VRFCoordinatorV2Mock", deployer)

              entranceFee = await raffle.getEntranceFee()

              interval = await raffle.getInterval()
          })

          describe("constructor", () => {
              it("initializes the raffle correctly", async () => {
                  const raffleState = await raffle.getRaffleState()

                  assert.equal(raffleState.toString(), "0")
                  assert.equal(
                      interval.toString(),
                      networkConfig[network.config.chainId]["keepersUpdateInterval"]
                  )
              })
          })

          describe("enterRaffle", () => {
              it("Revert when you don't pay enough", async () => {
                  await expect(raffle.enterRaffle()).to.be.reverted
              })

              it("records players when they enter", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  const player = await raffle.getPlayer(0)
                  assert.equal(player, deployer)
              })
              // test emits print
              it("emits event on enter", async () => {
                  await expect(raffle.enterRaffle({ value: entranceFee })).to.be.emit(
                      raffle,
                      "RaffleEnter"
                  )
              })

              it("doesn't allow entrance when raffle is calculation", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await raffle.provider.send("evm_increaseTime", [interval.toNumber() + 1])
                  await network.provider.request({ method: "evm_mine", params: [] })

                  await raffle.performUpkeep([])

                  await expect(raffle.enterRaffle({ value: entranceFee })).to.be.reverted
              })
          })

          describe("checkUpkeep", () => {
              it("returns false if people haven't sent any ETH", async () => {
                  // await raffle.enterRaffle({ value: entranceFee })
                  await raffle.provider.send("evm_increaseTime", [interval.toNumber() + 1])
                  await network.provider.request({ method: "evm_mine", params: [] })
                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep([])
                  assert(!upkeepNeeded)
              })

              it("returns false if raffle isn't open", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
                  await network.provider.request({ method: "evm_mine", params: [] })
                  await raffle.performUpkeep([]) // changes the state to calculating
                  const raffleState = await raffle.getRaffleState() // stores the new state
                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep("0x") // upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers)
                  assert.equal(raffleState.toString() == "1", upkeepNeeded == false)
              })

              it("returns false if enough time hasn't passed", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber() - 5])
                  await network.provider.request({ method: "evm_mine", params: [] })
                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep("0x")
                  assert(!upkeepNeeded)
              })

              it("returns true if enough time has passed, has players, eth, and is open", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
                  await network.provider.request({ method: "evm_mine", params: [] })
                  const { upkeepNeeded } = await raffle.callStatic.checkUpkeep("0x") // upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers)
                  assert(upkeepNeeded)
              })
          })

          describe("performUpkeep", () => {
              it("it can only run if checkupkeep is true", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber()])
                  await network.provider.request({ method: "evm_mine", params: [] })

                  const tx = await raffle.performUpkeep([])

                  assert(tx)
              })

              it("reverts when checkupkeep is false", async () => {
                  await expect(raffle.performUpkeep([])).to.be.reverted
              })

              it("updates the raffle state, emits and event, and calls the vrf coordinator", async () => {
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber()])
                  await network.provider.request({ method: "evm_mine", params: [] })

                  const txResponse = await raffle.performUpkeep([])

                  const txReceipt = await txResponse.wait(1)

                  const raffleState = await raffle.getRaffleState()
                  const requestId = txReceipt.events[1].args.requestId

                  assert(requestId.toNumber() > 0)
                  assert(raffleState == 1) // 0 = open, 1 = calculating
              })
          })

          describe("fulfillRandomWords", () => {
              beforeEach(async () => {
                  // await fundMe.provider.getBalance(fundMe.address)
                  // console.log((await raffle.provider.getBalance(raffle.address)).toString())
                  await raffle.enterRaffle({ value: entranceFee })
                  await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
                  await network.provider.request({ method: "evm_mine", params: [] })
              })
              it("can only be called after performupkeep", async () => {
                  await expect(
                      vrfCoordinatorV2Mock.fulfillRandomWords(0, raffle.address) // reverts if not fulfilled
                  ).to.be.revertedWith("nonexistent request")
                  await expect(
                      vrfCoordinatorV2Mock.fulfillRandomWords(1, raffle.address) // reverts if not fulfilled
                  ).to.be.revertedWith("nonexistent request")
              })

              it("picks a winner, resets, and sends money", async () => {
                  // 1. 制造多个用户参与
                  accounts = await ethers.getSigners()
                  const additionalEntrances = 3
                  const startingIndec = 1
                  // console.log("account1:" + (await accounts[1].getBalance()))
                  for (let i = startingIndec; i < startingIndec + additionalEntrances; i++) {
                      const raffleContract = await raffle.connect(accounts[i])
                      await raffleContract.enterRaffle({ value: entranceFee })
                  }
                  // console.log("account1:" + (await accounts[1].getBalance()))
                  // 2. 监听 等待随机数返还
                  await new Promise(async (reslove, reject) => {
                      raffle.once("WinnerPicked", async () => {
                          try {
                              const recentWinner = await raffle.getRecentWinner()
                              const playerNumber = await raffle.getNumberOfPlayers()
                              //   const randomWord = await raffle.getRandomWord()
                              //   console.log(randomWord.toString())
                              //   console.log(recentWinner)
                              //   console.log(accounts[0].address)
                              //   console.log(accounts[1].address)   √
                              //   console.log(accounts[2].address)
                              //   console.log(accounts[3].address)
                              //   console.log("account1:" + (await accounts[1].getBalance()))
                              const raffleState = await raffle.getRaffleState()
                              const winnerBalance = await accounts[1].getBalance()

                              assert.equal(recentWinner.toString(), accounts[1].address)
                              assert.equal(playerNumber.toString(), "0")
                              assert.equal(raffleState.toString(), "0")
                              // console.log(startingBalance.toString())
                              // console.log(winnerBalance.toString())

                              assert.equal(
                                  winnerBalance.toString(),
                                  startingBalance
                                      .add(entranceFee.mul(additionalEntrances).add(entranceFee))
                                      .toString()
                              )

                              reslove()
                          } catch (e) {
                              reject(e)
                          }
                      })

                      const startContractBalance = await raffle.provider.getBalance(raffle.address)

                      const txResponse = await raffle.performUpkeep([])
                      const txReceipt = await txResponse.wait(1)

                      const startingBalance = await accounts[1].getBalance()

                      await vrfCoordinatorV2Mock.fulfillRandomWords(
                          txReceipt.events[1].args.requestId,
                          raffle.address
                      )
                  })
              })
          })
      })
