const Noise = artifacts.require("Noise");

module.exports = function(deployer) {
  deployer.deploy(Noise);
};
