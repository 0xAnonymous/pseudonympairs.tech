contract Polytopia {

    uint constant period = 4 weeks;
    uint constant genesis = 198000;

    uint constant rngvote = 2 weeks;
    uint constant randomize = 3 weeks;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }
    function t(int _periods) public view returns (uint) { return schedule() + uint(_periods)*period; }

    enum Rank { None, Commit, Vote, Pseudonym, Court }
    enum Token { Personhood, Registration, Immigration }

    mapping (uint => uint) public seed;
    mapping (uint => uint) public entropy;

    mapping (uint => uint) public hour;
    uint[] public clockwork;

    function scheduleHour(uint _t) internal {
        if(clockwork.length == 0) clockwork = new uint[](24);
        uint randomHour = seed[_t] % clockwork.length;
        if(clockwork[randomHour] == 0) hour[_t] = randomHour;
        else hour[_t] = clockwork[randomHour];
        if(clockwork[clockwork.length - 1] == 0) clockwork[randomHour] = clockwork.length - 1;
        else clockwork[randomHour] = clockwork[clockwork.length - 1];
        clockwork.pop();
    }

    struct Reg {
        Rank rank;
        uint id;
        bool verified;
    }
    mapping (uint => mapping (address => Reg)) public registry;

    mapping (uint => address[]) public pseudonymIndex;
    mapping (uint => uint) public shuffled;

    mapping (uint => mapping (uint => address)) public courtIndex;
    mapping (uint => uint) public courts;

    struct Pair {
        bool[2] verified;
        bool disputed;
    }    
    mapping (uint => mapping (uint => Pair)) public pair;
    mapping (uint => mapping (uint => bool[2])) public court;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    mapping (uint => mapping (uint => uint)) public points;
    mapping (uint => uint[]) public leaderboard;
    mapping (uint => mapping (uint => uint)) public leaderboardIndex;

    struct Unit {
        uint start;
        uint end;
    }
    mapping (uint => mapping (uint => Unit)) public segments;

    constructor() public {
        uint _t = schedule();
        balanceOf[_t+period][Token.Registration][msg.sender] = 2**256-1;
        balanceOf[_t+period*2][Token.Registration][msg.sender] = 2**256-1;
    }

    function _shuffle(uint _t) internal {
        if(shuffled[_t] == 0) { 
            entropy[_t] = seed[_t] = uint(pseudonymIndex[_t][leaderboard[_t][0]]);
            scheduleHour(_t);
        }
        uint randomNumber = shuffled[_t] + entropy[_t]%(pseudonymIndex[_t].length - shuffled[_t]);
        entropy[_t] = uint(keccak256(abi.encodePacked(entropy[_t], pseudonymIndex[_t][randomNumber])));
        (pseudonymIndex[_t][shuffled[_t]], pseudonymIndex[t(0)][randomNumber]) = (pseudonymIndex[_t][randomNumber], pseudonymIndex[_t][shuffled[_t]]); 
        registry[_t][pseudonymIndex[_t][shuffled[_t]]].id = shuffled[_t];
        shuffled[_t]++;
    }
    function shuffle() public {
        uint _t = schedule(); require(block.timestamp > _t + randomize);
        require(registry[_t][msg.sender].rank == Rank.Vote);
        registry[_t][msg.sender].rank = Rank.Pseudonym;
        _shuffle(_t);
    }
    function lateShuffle(uint _iterations) public { for (uint i = 0; i < _iterations; i++) _shuffle(t(-1)); }
    
    function register() public {
        uint _t = schedule(); require(block.timestamp < _t + rngvote);
        require(registry[_t][msg.sender].rank == Rank.None && balanceOf[_t][Token.Registration][msg.sender] >= 1);
        balanceOf[_t][Token.Registration][msg.sender]--;
        pseudonymIndex[_t].push(msg.sender);
        registry[_t][msg.sender].rank = Rank.Commit;
        balanceOf[_t+period*2][Token.Immigration][msg.sender]++;
    }
    function immigrate() public {
        uint _t = schedule(); require(block.timestamp < _t + rngvote);
        require(registry[_t][msg.sender].rank == Rank.None && balanceOf[_t][Token.Immigration][msg.sender] >= 1);
        balanceOf[_t][Token.Immigration][msg.sender]--;
        registry[_t][msg.sender].id = courts[_t];
        courtIndex[_t][courts[_t]] = msg.sender;
        balanceOf[_t][Token.Immigration][pseudonymIndex[_t-period*2][courts[_t]%pseudonymIndex[_t-period].length]]++;
        courts[_t]++;
        registry[_t][msg.sender].rank = Rank.Court;
    }

    function _dispute(uint _t, uint _pair) internal {
        require(registry[_t][msg.sender].rank == Rank.Pseudonym);
        pair[_t][_pair].disputed = true; 
    }
    function dispute() public {
        uint _t = t(-2);
        uint _pair = registry[_t][msg.sender].id/2;
        require(pair[_t][_pair].verified[0] == false || pair[_t][_pair].verified[1] == false);
        _dispute(_t, _pair);
    }
    function premeetDispute() public { uint _t = t(-1); _dispute(_t, registry[_t][msg.sender].id/2); }
    function _reassign(uint _t, uint _pair) internal {
        require(pair[_t][_pair].disputed == true);
        uint _court = uint(keccak256(abi.encodePacked(msg.sender, _pair)))%pseudonymIndex[_t].length;
        uint i = 1;
        while(courtIndex[_t][_court*i] != address(0)) i++;
        registry[_t][msg.sender].id = _court*i;
    }
    function _reassignCourt(uint _t) internal {
        require(registry[_t][msg.sender].rank == Rank.Court);
        uint _pair = registry[_t][msg.sender].id%pseudonymIndex[_t].length/2;
        _reassign(_t, _pair);
    }
    function _reassignPseudonym(uint _t) internal {
        require(registry[_t][msg.sender].rank == Rank.Pseudonym);
        uint _pair = registry[_t][msg.sender].id/2;
        _reassign(_t, _pair);
        registry[_t][msg.sender].rank = Rank.Court;
    }
    function reassignCourt() public { _reassignCourt(t(-2)); } function premeetReassignCourt() public { _reassignCourt(t(-1)); }
    function reassignPseudonym() public { _reassignPseudonym(t(-2)); } function premeetReassignPseudonym() public { _reassignPseudonym(t(-1)); }

    function _completeVerification(uint _t, uint _pair) internal {
        require(pair[_t][_pair].verified[0] == true && pair[_t][_pair].verified[1] == true);
        require(registry[_t][msg.sender].verified == false);
        balanceOf[_t+period*2][Token.Personhood][msg.sender]++;
        balanceOf[_t+period*2][Token.Registration][msg.sender]++;
        registry[_t][msg.sender].verified = true;
    }
    function completeVerificationCourt() public {
        uint _t = t(-2); require(registry[_t][msg.sender].rank == Rank.Court);
        uint _court = registry[_t][msg.sender].id;
        require(court[_t][_court][0] == true && court[_t][_court][1] == true);
        _completeVerification(_t, _court%pseudonymIndex[_t].length/2);
    }
    function completeVerificationPseudonym() public {
        uint _t = t(-2); require(registry[_t][msg.sender].rank == Rank.Pseudonym);
        _completeVerification(_t, registry[_t][msg.sender].id/2);
    }
    function _verify(uint _t, address _signer, uint _pairAccount, uint _pairSigner) internal view {
        require(block.timestamp > _t + hour[_t]*3600);
        require(registry[_t][_signer].rank == Rank.Pseudonym);
        require(pair[_t][_pairAccount].disputed == false);
        require(_pairAccount == _pairSigner);
    }
    function _verifyPseudonym(uint _t, address _account, address _signer) internal {
        require(registry[_t][_account].rank == Rank.Pseudonym);
        require(_account != _signer);
        uint _pair = registry[_t][_account].id/2;
        uint peer = registry[_t][_signer].id;
        _verify(_t, _signer, _pair, peer/2);
        pair[_t][_pair].verified[peer%2] = true;
    }
    function _verifyCourt(uint _t, address _account, address _signer) internal {
        require(registry[_t][_account].rank == Rank.Court);
        uint _court = registry[_t][_account].id;
        uint peer = registry[_t][_signer].id;
        _verify(_t, _signer, _court%pseudonymIndex[_t].length/2, peer/2);
        court[_t][_court][peer%2] = true;
    }
    function verifyPseudonym(address _pseudonym) public { _verifyPseudonym(t(-2), _pseudonym, msg.sender); }
    function verifyCourt(address _court) public { _verifyCourt(t(-2), _court, msg.sender); }
    
    function msgHash(uint _t) internal view returns (bytes32) { return keccak256(abi.encodePacked(msg.sender, _t+period*2)); }

    function pseudonymSignature(bytes32 r, bytes32 s, uint8 v) public {
        uint _t = t(-2); _verifyPseudonym(_t, msg.sender, ecrecover(msgHash(_t), v, r, s));
    }
    function courtSignature(bytes32 r, bytes32 s, uint8 v) public {
        uint _t = t(-2); _verifyCourt(_t, msg.sender, ecrecover(msgHash(_t), v, r, s));
    }
    function courtDoubleSignature(bytes32[2] memory r, bytes32[2] memory s, uint8[2] memory v) public {
        uint _t = t(-2); bytes32 _msgHash = msgHash(_t);
        _verifyCourt(_t, msg.sender, ecrecover(_msgHash, v[0], r[0], s[0]));
        _verifyCourt(_t, msg.sender, ecrecover(_msgHash, v[1], r[1], s[1]));
    }
    function claimPersonhood() public {
        uint _t = schedule();
        require(proofOfPersonhood[_t][msg.sender] == 0 && balanceOf[_t][Token.Personhood][msg.sender] >= 1);
        balanceOf[_t][Token.Personhood][msg.sender]--;
        population[_t]++;
        proofOfPersonhood[_t][msg.sender] = population[_t];
        personhoodIndex[_t][population[_t]] = msg.sender;
    }
    function _transfer(uint _t, address _from, address _to, uint _value, Token _token) internal { 
        require(balanceOf[_t][_token][_from] >= _value);
        balanceOf[_t][_token][_from] -= _value;
        balanceOf[_t][_token][_to] += _value;        
    }
    function transfer(address _to, uint _value, Token _token) public { _transfer(schedule(), msg.sender, _to, _value, _token); }    
    function approve(address _spender, uint _value, Token _token) public {
        allowed[schedule()][_token][msg.sender][_spender] = _value;
    }
    function transferFrom(address _from, address _to, uint _value, Token _token) public {
        uint _t = schedule();
        require(allowed[_t][_token][_from][msg.sender] >= _value);
        _transfer(_t, _from, _to, _value, _token);
        allowed[_t][_token][_from][msg.sender] -= _value;
    }
    function vote(uint _id) public {
        uint _t = schedule(); require(block.timestamp > _t + rngvote && block.timestamp < _t + randomize); 

        require(registry[_t][msg.sender].rank == Rank.Commit);
        registry[_t][msg.sender].rank = Rank.Vote;

        uint score = points[_t][_id];

        if(score == 0) {
            leaderboardIndex[_t][_id] = leaderboard[_t].length;
            if(segments[_t][1].end == 0) segments[_t][1].end = leaderboard[_t].length; 
            leaderboard[_t].push(_id);
        }
        else {
            uint index = leaderboardIndex[_t][_id];
            uint nextSegment = segments[_t][score].end;
            if(nextSegment != index) (leaderboard[_t][nextSegment], leaderboard[_t][index]) = (leaderboard[_t][index], leaderboard[_t][nextSegment]);
	        if(segments[_t][score].start == nextSegment) { segments[_t][score].start = 0; segments[_t][score].end = 0; }
            else segments[_t][score].end--;

            if(segments[_t][score+1].end == 0) segments[_t][score+1].end = nextSegment;
            segments[_t][score+1].start = nextSegment;
        }
        points[_t][_id]++;
    }
}
