contract OnlinePseudonymParties {

    uint entropy;

    function getRandomNumber() internal returns (uint){ return entropy = uint(keccak256(abi.encodePacked(blockhash(block.number - 1), entropy))); }

    uint constant public period = 4 weeks;

    function schedule() public view returns (uint) { return 198000 + ((block.timestamp - 198000) / period) * period; }

    enum Rank { Court, Pair }

    enum Token { Personhood, Registration, Immigration }

    struct Reg {
        Rank rank;
        uint id;
        bool verified;
    }
    mapping (uint => mapping (address => Reg)) public registry;
    mapping (uint => address[]) public shuffler;
    mapping (uint => mapping (Rank => mapping (uint => bool[2]))) public judgement;
    mapping (uint => mapping (uint => bool)) public disputed;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    function registered(uint _t) public view returns (uint) { return shuffler[_t].length; }

    function register() public {
        uint t = schedule();
        require(block.timestamp < t + 2 weeks);
        require(registry[t][msg.sender].id == 0 && balanceOf[t][Token.Registration][msg.sender] >= 1);
        balanceOf[t][Token.Registration][msg.sender]--;
        uint id = 1;
        if(registered(t) != 0) {
            id += getRandomNumber() % registered(t);
            shuffler[t].push(shuffler[t][id-1]);
            registry[t][shuffler[t][id-1]].id = registered(t);
        }
        else shuffler[t].push();

        shuffler[t][id-1] = msg.sender;
        registry[t][msg.sender] = Reg(Rank.Pair, id, false);
    }
    function immigrate() external {
        uint t = schedule();
        require(registry[t][msg.sender].id == 0 && balanceOf[t][Token.Immigration][msg.sender] >= 1);
        balanceOf[t][Token.Immigration][msg.sender]--;
        registry[t][msg.sender].id = 1 + getRandomNumber()%(2**256-1);
    }

    function isVerified(Rank _rank, uint _unit, uint _t) public view returns (bool) {
        return (judgement[_t][_rank][_unit][0] == true && judgement[_t][_rank][_unit][1] == true);
    }

    function dispute(bool _early) external {
        uint t = schedule();
        if(_early == true) require(block.timestamp > t + 2 weeks);
        else t -= period;
        require(registry[t][msg.sender].rank == Rank.Pair);
        uint id = registry[t][msg.sender].id;
        uint pair = (id+1)/2;
        if(_early == false) require(!isVerified(Rank.Pair, pair, t));
        disputed[t][pair] = true;
    }
    function reassign(bool _early) external {
        uint t = schedule();
        if(_early != true) t -= period;
        uint id = registry[t][msg.sender].id;
        uint pair = 1 + ((id - 1)/(uint(registry[t][msg.sender].rank) + 1))%registered(t)/2;
        require(disputed[t][pair] == true);
        delete registry[t][msg.sender];
        registry[t][msg.sender].id = 1 + getRandomNumber()%(2**256-1);
    }
    
    function _verify(address _account, address _signer, uint _t) internal {
        require(block.timestamp > _t + (uint(keccak256(abi.encode(_t)))%24) * 1 hours);
        require(registry[_t][_signer].rank == Rank.Pair && _account != _signer);
        Rank rank = registry[_t][_account].rank;
        uint temp = (registry[_t][_account].id-1)/(1 + uint(rank));
        uint unit = 1 + temp;
        uint pair = 1 + temp%registered(_t)/2;
        require(disputed[_t][pair] == false);
        uint peer = registry[_t][_signer].id;
        require(pair == (peer+1)/2);
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
            pair = 1 + (id - 1)%registered(t)/2;
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

    function initialize() external {
        uint t = schedule();
        require(registered(t-period) < 2 && registered(t) < 2);
        balanceOf[t][Token.Registration][msg.sender]++;
        register();
    }    
}

contract Factory {

    function newContract() external {
        new OnlinePseudonymParties();
    }
}
