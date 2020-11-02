contract Polytopia {

    uint constant public period = 4 weeks;
    uint constant public genesis = 1604127600;

    uint constant public randomize = 2 weeks;
    uint constant public premeet = 3 weeks;

    uint public hour;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }

    uint entropy;

    function initializeRandomization() internal {
        entropy = uint(blockhash(block.number-1));
        hour = (entropy%24)*1 hours;
    }

    enum Rank { Court, Pair }

    enum Token { Personhood, Registration, Immigration }

    struct Reg {
        Rank rank;
        uint id;
        bool verified;
    }
    mapping (uint => mapping (address => Reg)) public registry;
    mapping (uint => mapping (Rank => mapping (uint => address))) public registryIndex;
    mapping (uint => mapping (Rank => uint)) public registered;
    mapping (uint => uint) public shuffled;
    mapping (uint => mapping (address => bool)) public committed;
    mapping (uint => mapping (Rank => mapping (uint => bool[2]))) public judgement;
    mapping (uint => mapping (uint => bool)) public disputed;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    function inState(uint _prev, uint _next, uint _t) internal view returns (bool) {
        if(_prev != 0) return (block.timestamp > _t + _prev);
        if(_next != 0) return (block.timestamp < _t + _next);
    }

    constructor() public {
        address genesisAccount = 0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308;
        uint genesisPopulation = 2;
        balanceOf[schedule()][Token.Registration][genesisAccount] = genesisPopulation;
        balanceOf[schedule()][Token.Immigration][genesisAccount] = genesisPopulation;
    }

    function _register(Rank _rank) internal {
        uint t = schedule();
        require(inState(0, randomize, t));
        require(registry[t][msg.sender].id == 0 && registry[t][msg.sender].rank != Rank.Pair);
        Token _token = Token(2-uint(_rank));
        require(balanceOf[t][_token][msg.sender] >= 1);
        balanceOf[t][_token][msg.sender]--;
        registered[t][_rank]++;
        registryIndex[t][_rank][registered[t][_rank]] = msg.sender;
        registry[t][msg.sender].rank = _rank;
        if(_rank != Rank.Pair) registry[t][msg.sender].id = registered[t][Rank.Court];
    }
    function register() external { _register(Rank.Pair); }
    function immigrate() external { _register(Rank.Court); }

    function _shuffle(uint _t) internal {
        if(shuffled[_t] == 0) initializeRandomization();
        shuffled[_t]++;
        uint _shuffled = shuffled[_t];
        uint randomNumber = _shuffled + entropy%(registered[_t][Rank.Pair] + 1 - _shuffled);
        entropy = uint(keccak256(abi.encodePacked(entropy, registryIndex[_t][Rank.Pair][randomNumber])));
        (registryIndex[_t][Rank.Pair][_shuffled], registryIndex[_t][Rank.Pair][randomNumber]) =
        (registryIndex[_t][Rank.Pair][randomNumber], registryIndex[_t][Rank.Pair][_shuffled]); 
        registry[_t][registryIndex[_t][Rank.Pair][_shuffled]].id = _shuffled;
    }
    function shuffle() external {
        uint t = schedule(); 
        require(inState(randomize, premeet, t));
        require(registry[t][msg.sender].rank == Rank.Pair && committed[t][msg.sender] == false);
        committed[t][msg.sender] = true;
        _shuffle(t);
    }
    function lateShuffle(uint _iterations) external { 
        uint t = schedule();
        require(inState(premeet, 0, t));
        for (uint i = 0; i < _iterations; i++) _shuffle(t); 
    }

    function isVerified(Rank _rank, uint _unit, uint t) public view returns (bool) {
        return (judgement[t][_rank][_unit][0] == true && judgement[t][_rank][_unit][1] == true);
    }

    function dispute(bool _premeet) external {
        uint t = schedule();
        if(_premeet != true) t -= period;
        uint id = registry[t][msg.sender].id;
        require(registry[t][msg.sender].rank == Rank.Pair && id != 0);
        uint pair = (id+1)/2;
        if(_premeet == false) require(!isVerified(Rank.Pair, pair, t));
        disputed[t][pair] = true;
    }
    function reassign(bool _premeet) external {
        uint t = schedule();
        if(_premeet != true) t -= period;        
        uint id = registry[t][msg.sender].id;
        require(id != 0);
        uint countPairs = registered[t][Rank.Pair]/2;
        uint pair;
        if(registry[t][msg.sender].rank == Rank.Pair) {
            pair = (id + 1)/2;
            registry[t][msg.sender].rank = Rank.Court;
        }
        else pair = 1 + (id - 1)%countPairs;
        require(disputed[t][pair] == true);
        uint court = 1 + uint(keccak256(abi.encodePacked(msg.sender, pair)))%countPairs;
        while(registryIndex[t][Rank.Court][court] != address(0)) court += countPairs;
        registry[t][msg.sender].id = court;
        registryIndex[t][Rank.Court][court] = msg.sender;        
    }
    function _verify(address _account, address _signer, uint _t) internal {
        require(inState(hour, 0, _t));
        require(_account != _signer);
        require(registry[_t][_signer].rank == Rank.Pair && committed[_t][_signer] == true);
        uint id = registry[_t][_account].id;
        require(id != 0);        
        Rank rank = registry[_t][_account].rank;
        uint unit;
        uint pair;
        if(rank == Rank.Pair) {
            pair = (id + 1)/2;
            unit = pair;
        }
        else {
            unit = id;
            pair = 1 + (unit - 1)%(registered[_t][Rank.Pair]/2);
        }
        require(disputed[_t][pair] == false);
        uint peer = registry[_t][_signer].id;
        require(peer != 0 && pair == (peer+1)/2);
        judgement[_t][rank][unit][peer%2] = true;
    }
    function verify(address _account) external { _verify(_account, msg.sender, schedule()-period); }

    function uploadSignature(address[] calldata _account, bytes32[] calldata r, bytes32[] calldata s, uint8[] calldata v) external {
        uint t = schedule()-period;
        for(uint i = 0; i < _account.length; i++) {
            bytes32 _msgHash = keccak256(abi.encodePacked(_account[i], t));
            _verify(_account[i], ecrecover(_msgHash, v[i], r[i], s[i]), t);
        }
    }
    function completeVerification() external {
        uint t = schedule()-period;
        require(registry[t][msg.sender].verified == false);
        uint id = registry[t][msg.sender].id;
        uint pair;
        if(registry[t][msg.sender].rank == Rank.Court) {
            require(isVerified(Rank.Court, id, t));
            pair = 1 + (id - 1)%(registered[t][Rank.Pair]/2);
        }
        else pair = (id + 1) /2;
        require(isVerified(Rank.Pair, pair, t));
        balanceOf[t+period][Token.Personhood][msg.sender]++;
        balanceOf[t+period][Token.Registration][msg.sender]++;
        balanceOf[t+period][Token.Immigration][msg.sender]++;        
        registry[t][msg.sender].verified = true;
    }
    function claimPersonhood() external {
        uint t = schedule();
        require(proofOfPersonhood[t][msg.sender] == 0 && balanceOf[t][Token.Personhood][msg.sender] >= 1);
        balanceOf[t][Token.Personhood][msg.sender]--;
        population[t]++;
        proofOfPersonhood[t][msg.sender] = population[t];
        personhoodIndex[t][population[t]] = msg.sender;
    }

    function _transfer(uint _t, address _from, address _to, uint _value, Token _token) internal { 
        require(balanceOf[_t][_token][_from] >= _value);
        balanceOf[_t][_token][_from] -= _value;
        balanceOf[_t][_token][_to] += _value;        
    }
    function transfer(address _to, uint _value, Token _token) external {
        _transfer(schedule(), msg.sender, _to, _value, _token);
    }
    function approve(address _spender, uint _value, Token _token) external {
        allowed[schedule()][_token][msg.sender][_spender] = _value;
    }
    function transferFrom(address _from, address _to, uint _value, Token _token) external {
        uint t = schedule();
        require(allowed[t][_token][_from][msg.sender] >= _value);
        _transfer(t, _from, _to, _value, _token);
        allowed[t][_token][_from][msg.sender] -= _value;
    }
}
