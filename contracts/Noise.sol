pragma solidity >= 0.6.3;
// solium-disable security/no-block-members

/// @title Noise DAO for funding of proposals
/// @notice Members can propose ways to spend funds and sponsor new members.
///   Any member can veto a proposal or a sponsored member.
///   Members can sponsor a new member or submit a proposal (not both) once a week.
contract Noise {
  struct Member {
    // sponsor is the address of the Member who sponsored this Member.
    address sponsor;
    // handle is a UTF8 encoded nickname that this Member goes by.
    bytes32 handle;
    // timeJoined is the timestamp of the block in which this member was sponsored.
    uint256 timeJoined;
    // lastChange is the timestamp of the block in which this member last sponsered a new member or made a new proposal.
    uint256 lastChange;
  }

  struct Proposal {
    // sponsor is the address of the member who submitted this proposal
    address sponsor;
    // url is a UTF8 link to the full proposal specification
    bytes32[4] url;
    // digest is the sha3_256 digest of the proposal.
    bytes32 digest;
    // wallet is the address to send funds to for this proposal.
    address payable wallet;
    // value is the amount of wei to send to the wallet
    uint256 value;
    // timeSubmitted is the timestamp of the block in which this proposal was submitted.
    uint256 timeSubmitted;
  }

  event NewMember(address indexed sponsor, address indexed member);
  event MemberVetoed(address indexed vetoer, address indexed vetoed);
  event NewProposal(address indexed sponsor, bytes32 indexed proposal);
  event ProposalVetoed(address indexed vetoer, bytes32 indexed proposal);
  event ProposalClaimed(bytes32 indexed proposal, uint256 value);
  event NewDonation(address indexed donor, uint256 value);

  // Mapping of account addresses to membership data.
  mapping (address => Member) public members;
  // Mapping of proposal hash to proposal data.
  mapping (bytes32 => Proposal) public proposals;
  mapping (bytes32 => bool) public handleTaken;

  // One week in seconds.
  uint256 public constant ONE_WEEK = 60*60*24*7;

  modifier onlyMembers() {
    require(members[msg.sender].sponsor != address(0), 'sender is not a member');
    require(block.timestamp - members[msg.sender].timeJoined >= ONE_WEEK, 'sender is not yet a full member');
    _;
  }

  modifier rateLimited(uint256 cooldown) {
    require(
      block.timestamp - members[msg.sender].lastChange >= cooldown,
      'not enough time has passed since the last member action'
    );
    _;
    members[msg.sender].lastChange = block.timestamp;
  }

  function sponsorMember(address member,  bytes32 handle) external onlyMembers rateLimited(ONE_WEEK) {
    require(members[member].sponsor == address(0), 'address is already a member');
    require(!handleTaken[handle], 'handle is already taken');

    // Add the member information to the mapping.
    members[member] = Member({
      sponsor: msg.sender,
      handle: handle,
      timeJoined: block.timestamp,
      lastChange: 0
    });
    handleTaken[handle] = true;
    emit NewMember(msg.sender, member);
  }

  function vetoMember(address member) external onlyMembers {
    require(members[member].sponsor != address(0), 'address is not a member');
    require(block.timestamp - members[member].timeJoined < ONE_WEEK, 'member can no longer be vetoed');
    delete members[member];
    emit MemberVetoed(msg.sender, member);
  }

  function submitProposal(bytes32[4] calldata url, bytes32 digest, address payable wallet, uint256 value)
    external
    onlyMembers
    rateLimited(ONE_WEEK)
  {
    require(address(this).balance > value, 'contract has insuficient funds for this proposal');

    Proposal memory proposal = Proposal({
      sponsor: msg.sender,
      url: url,
      digest: digest,
      wallet: wallet,
      value: value,
      timeSubmitted: block.timestamp
    });
    bytes32 hash = keccak256(abi.encodePacked(msg.sender, url, digest, wallet, value, block.timestamp));
    require(proposals[hash].timeSubmitted == 0, 'proposal has already been submitted');
    proposals[hash] = proposal;
    emit NewProposal(msg.sender, hash);
  }


  function vetoProposal(bytes32 proposal) external onlyMembers {
    require(block.timestamp - proposals[proposal].timeSubmitted < ONE_WEEK, 'proposal can no longer be vetoed');
    proposals[proposal].value = 0;
    emit ProposalVetoed(msg.sender, proposal);
  }


  function claimProposal(bytes32 hash) external {
    Proposal storage proposal = proposals[hash];
    require(block.timestamp - proposal.timeSubmitted >= ONE_WEEK, 'proposal cannot be claimed yet');
    if (proposal.value > 0) {
      proposal.wallet.transfer(proposal.value);
      emit ProposalClaimed(hash, proposal.value);
      proposal.value = 0;
    }
  }

  function donate() public payable {
    emit NewDonation(msg.sender, msg.value);
  }

}
