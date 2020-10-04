contract Polytopia {

    uint constant public period = 4 weeks;
    uint constant public genesis = 1599894000;

    uint constant public rngvote = 2 weeks;
    uint constant public randomize = 3 weeks;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }
    function t(int _periods) public view returns (uint) { return schedule() + uint(_periods)*period; }

    mapping (uint => uint) public seed;
    mapping (uint => uint) public entropy;

    mapping (uint => uint) public hour;
    uint[] public clockwork;
    uint clock_nonce;

    function scheduleHour(uint _t) internal {
        if(clock_nonce == 0) clock_nonce = 24;
        uint _index = seed[_t] % clock_nonce;
        clock_nonce--;
        hour[_t] = clockwork[_index];
        clockwork[_index] = clockwork[clock_nonce];
        clockwork[clock_nonce] = clock_nonce;
    }

    enum Rank { Court, Pair }
    enum Status { None, Commit, Vote, Active, Verified }
    enum Token { Personhood, Registration, Immigration }

    struct Reg {
        Rank rank;
        uint id;
        Status status;
    }
    mapping (uint => mapping (address => Reg)) public registry;
    mapping (uint => mapping (Rank => mapping (uint => address))) public registryIndex;
    mapping (uint => mapping (Rank => uint)) public registered;
    mapping (uint => uint) public shuffled;
    mapping (uint => mapping (Rank => mapping (uint => bool[2]))) public judgement;
    mapping (uint => mapping (uint => bool)) public disputed;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    mapping (uint => mapping (uint => uint)) public points;
    mapping (uint => uint[]) public leaderboard;
    mapping (uint => mapping (uint => uint)) public leaderboardIndex;

    struct Score {
        uint start;
        uint end;
    }
    mapping (uint => mapping (uint => Score)) public segments;
    
    function inState(uint _prev, uint _next, uint _t) internal view {
        if(_prev != 0) require(block.timestamp > _t + _prev);
        if(_next != 0) require(block.timestamp < _t + _next);
    }

    constructor() public {
        for(uint i; i<24; i++) clockwork.push(i);
        uint _t = schedule();
        balanceOf[_t+period][Token.Registration][msg.sender] = 2**256-1;
        balanceOf[_t+period*2][Token.Registration][msg.sender] = 2**256-1;
    }
    function consultOracle(uint _t) internal {
        entropy[_t] = seed[_t] = uint(registryIndex[_t][Rank.Pair][leaderboard[_t][0]]);
        scheduleHour(_t);
    }
    function _shuffle(uint _t) internal {
        if(shuffled[_t] == 0) consultOracle(_t);
        uint _shuffled = shuffled[_t];
        uint randomNumber = _shuffled + entropy[_t]%(registered[_t][Rank.Pair] - _shuffled);
        entropy[_t] = uint(keccak256(abi.encodePacked(entropy[_t], registryIndex[_t][Rank.Pair][randomNumber])));
        (registryIndex[_t][Rank.Pair][_shuffled], registryIndex[_t][Rank.Pair][randomNumber]) = (registryIndex[_t][Rank.Pair][randomNumber], registryIndex[_t][Rank.Pair][_shuffled]); 
        registry[_t][registryIndex[_t][Rank.Pair][_shuffled]].id = _shuffled;
        shuffled[_t]++;
    }
    function shuffle() public {
        uint _t = schedule(); inState(randomize, 0, _t);
        require(registry[_t][msg.sender].status == Status.Vote);
        registry[_t][msg.sender].rank = Rank.Pair;
        registry[_t][msg.sender].status = Status.Active;
        _shuffle(_t);
    }
    function lateShuffle(uint _iterations) public { for (uint i = 0; i < _iterations; i++) _shuffle(t(-1)); }

    function _registration(uint _t, Token _token, Rank _rank) internal {
        inState(0, rngvote, _t);
        require(registry[_t][msg.sender].status == Status.None);
        require(balanceOf[_t][_token][msg.sender] >= 1);
        balanceOf[_t][_token][msg.sender]--;
        registryIndex[_t][_rank][registered[_t][_rank]] = msg.sender;
        registered[_t][_rank]++;
    }
    function register() public {
        uint _t = schedule();
        _registration(_t, Token.Registration, Rank.Pair);
        registry[_t][msg.sender].status = Status.Commit;
        balanceOf[_t+period*2][Token.Immigration][msg.sender]++;
    }
    function immigrate() public {
        uint _t = schedule();
        registry[_t][msg.sender].id = registered[_t][Rank.Court];
        balanceOf[_t][Token.Immigration][registryIndex[_t-period*2][Rank.Pair][registered[_t][Rank.Court]%registered[_t-period*2][Rank.Pair]]]++;
        _registration(_t, Token.Immigration, Rank.Court);
        registry[_t][msg.sender].status = Status.Active;
    }
    
    function isVerified(Rank _rank, uint _unit, uint _t) public view returns (bool) {
        return (judgement[_t][_rank][_unit][0] == true && judgement[_t][_rank][_unit][1] == true);
    }

    function _dispute(uint _t, uint _pair) internal {
        require(registry[_t][msg.sender].rank == Rank.Pair);
        disputed[_t][_pair] = true; 
    }
    function dispute() public {
        uint _t = t(-2);
        uint pair = registry[_t][msg.sender].id/2;
        require(isVerified(Rank.Pair, pair, _t));
        _dispute(_t, pair);
    }
    function premeetDispute() public { uint _t = t(-1); _dispute(_t, registry[_t][msg.sender].id/2); }
    
    function _reassign(uint _t) internal {
        require(registry[_t][msg.sender].status == Status.Active);
        uint countPairs = registered[_t][Rank.Pair]/2;
        uint pair = (registry[_t][msg.sender].id/(1+uint(registry[_t][msg.sender].rank)))%countPairs;
        require(disputed[_t][pair] == true);
        uint court = uint(keccak256(abi.encodePacked(msg.sender, pair)))%countPairs;
        uint i = 1;
        while(registryIndex[_t][Rank.Court][court*i] != address(0)) i++;
        registry[_t][msg.sender].id = court*i;
        registry[_t][msg.sender].rank = Rank.Court;
    }
    function reassign() public { _reassign(t(-2)); } function premeetReassign() public { _reassign(t(-1)); }

    function completeVerification() public {
        uint _t = t(-2);
        require(registry[_t][msg.sender].status == Status.Active);
        Rank rank = registry[_t][msg.sender].rank;
        uint id = registry[_t][msg.sender].id;
        uint pair;
        if(rank == Rank.Court) {
            require(isVerified(Rank.Court, id, _t));
            pair = id%registered[_t][Rank.Pair]/2;
        }
        else pair = id/2;
        require(isVerified(Rank.Pair, pair, _t));
        balanceOf[_t+period*2][Token.Personhood][msg.sender]++;
        balanceOf[_t+period*2][Token.Registration][msg.sender]++;
        registry[_t][msg.sender].status = Status.Verified;
    }
    function _verify(address _account, address _signer, uint _t) internal {
        inState(hour[_t]*3600, 0, _t);
        require(registry[_t][_signer].rank == Rank.Pair);
        require(_account != _signer);
        Rank rank = registry[_t][_account].rank;
        uint unit = registry[_t][_account].id/(1+uint(rank));
        uint pair = unit%registered[_t][Rank.Pair]/2;
        require(disputed[_t][pair] == false);
        uint peer = registry[_t][_signer].id;
        require(pair == peer/2);
        judgement[_t][rank][unit][peer%2] = true;        
    }
    function verify(address _account) public { _verify(_account, msg.sender, t(-2)); }

    function msgHash(address _account, uint _t) internal pure returns (bytes32) { return keccak256(abi.encodePacked(_account, _t+period*2)); }

    function uploadSignature(bytes32 r, bytes32 s, uint8 v) public {
        uint _t = t(-2); _verify(msg.sender, ecrecover(msgHash(msg.sender, _t), v, r, s), _t);
    }
    function courtSignature(bytes32[2] memory r, bytes32[2] memory s, uint8[2] memory v) public {
        uint _t = t(-2); bytes32 _msgHash = msgHash(msg.sender, _t);
        _verify(msg.sender, ecrecover(_msgHash, v[0], r[0], s[0]), _t);
        _verify(msg.sender, ecrecover(_msgHash, v[1], r[1], s[1]), _t);
    }
    function massSignature(address[] memory _accounts, bytes32[] memory r, bytes32[] memory s, uint8[] memory v) public {
        uint _t = t(-2);
        for(uint i = 0; i< _accounts.length; i++) { _verify(_accounts[i], ecrecover(msgHash(_accounts[i], _t), v[i], r[i], s[i]), _t); }
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
        uint _t = schedule(); inState(rngvote, randomize, _t); 
        require(_id < registered[_t][Rank.Pair]);

        require(registry[_t][msg.sender].status == Status.Commit);
        registry[_t][msg.sender].status = Status.Vote;

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
