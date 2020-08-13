contract PseudonymPairs {
    
    uint entropy;
    function getRandomNumber() internal returns (uint){
        entropy = uint(keccak256(abi.encodePacked(now, msg.sender, blockhash(block.number - 1), entropy)));
        return entropy;
    }

    uint public maxValue = 2**256-1;
    
    uint public schedule;
    uint public period = 28 days;
    uint public hour;

    struct Reg {
        bool rank;
        uint id;
        bool verified;
    }
    mapping (uint => mapping (address => Reg)) public registry;
    mapping (uint => address[]) public shuffler;
    mapping (uint => mapping (address => bool[2])) public courts;
    
    struct Pair {
        bool[2] peers;
        bool disputed;
    }
    mapping (uint => mapping (uint => Pair)) public pairs;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;
    
    mapping (uint => mapping (uint => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (uint => mapping (address => mapping (address => uint)))) public allowed;

    constructor() public {
        schedule = 198000 + ((block.timestamp - 198000)/ 7 days) * 7 days - 21 days;
        hour = getRandomNumber()%24;
        balanceOf[schedule][1][msg.sender] = maxValue;
    }
    function pseudonymEvent() public view returns (uint) { return schedule + period + hour * 3600; }
    modifier scheduler() {
        if(block.timestamp > pseudonymEvent()) {
            schedule += period;
            hour = getRandomNumber()%24;
        }
        _;
    }
    function getSchedule() public scheduler returns (uint) { return schedule; }    

    function register() public scheduler {
        require(registry[schedule][msg.sender].id == 0 && balanceOf[schedule][1][msg.sender] >= 1);
        balanceOf[schedule][1][msg.sender]--;
        uint id = 1;
        if(shuffler[schedule].length != 0) {
            id += getRandomNumber() % shuffler[schedule].length;
            shuffler[schedule].push(shuffler[schedule][id-1]);
            registry[schedule][shuffler[schedule][id-1]].id = shuffler[schedule].length;
        }
        else shuffler[schedule].push();

        shuffler[schedule][id-1] = msg.sender;
        registry[schedule][msg.sender] = Reg(true, id, false);

        balanceOf[schedule+period][0][msg.sender]++;
    }
    function immigrate() public scheduler {
        require(registry[schedule][msg.sender].id == 0 && balanceOf[schedule][0][msg.sender] >= 1);
        balanceOf[schedule][0][msg.sender]--;
        registry[schedule][msg.sender].id = 1 + getRandomNumber()%maxValue;
        balanceOf[schedule][0][shuffler[schedule-period][getRandomNumber()%shuffler[schedule-period].length]]++;
    }
    function transferRegistrationKey(address _to) public scheduler {
        require(registry[schedule][msg.sender].id != 0 && registry[schedule][_to].id == 0);
        if(registry[schedule][msg.sender].rank == true) shuffler[schedule][registry[schedule][msg.sender].id-1] = _to;
        registry[schedule][_to] = registry[schedule][msg.sender];
        delete registry[schedule][msg.sender];
    }
    function pairVerified(uint _pair) public view returns (bool) {
        return (pairs[schedule-period][_pair].peers[0] == true && pairs[schedule-period][_pair].peers[1] == true);
    }
    function getPair(address _account) public view returns (uint) {
        if(registry[schedule-period][_account].rank == true) return (1 + registry[schedule-period][_account].id)/2;
        return 1 + registry[schedule-period][_account].id%(shuffler[schedule-period].length/2);
    }    
    function dispute() public scheduler {
        require(registry[schedule-period][msg.sender].rank == true);
        uint pair = getPair(msg.sender);
        require(!pairVerified(pair));
        pairs[schedule-period][pair].disputed = true;
    }
    function reassign() public scheduler {
        require(pairs[schedule-period][getPair(msg.sender)].disputed == true);
        delete registry[schedule-period][msg.sender];
        registry[schedule-period][msg.sender].id = 1 + getRandomNumber()%maxValue;
    }
    function completeVerification() public scheduler {
        require(pairVerified(getPair(msg.sender)) == true && registry[schedule-period][msg.sender].verified == false);
        if(registry[schedule-period][msg.sender].rank == false) {
            require(courts[schedule-period][msg.sender][0] == true && courts[schedule-period][msg.sender][1] == true);
        }
        balanceOf[schedule][1][msg.sender]++;
        balanceOf[schedule][2][msg.sender]++;
        registry[schedule-period][msg.sender].verified = true;
    }
    function _verify(address _account, address _signer) internal {
        require(registry[schedule-period][_signer].rank == true && _account != _signer);
        uint pair = getPair(_account);
        require(pair == getPair(_signer) && pairs[schedule-period][pair].disputed == false);
        uint peer = registry[schedule-period][_signer].id%2;
        if(registry[schedule-period][_account].rank == true) pairs[schedule-period][pair].peers[peer] = true;
        else courts[schedule-period][_account][peer] = true;
    }
    function verify(address _account) public scheduler {
	    _verify(_account, msg.sender);
    }
    function uploadSignature(address _account, bytes memory _signature) public scheduler {

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(_signature,0x20))
            s := mload(add(_signature,0x40))
            v := and(mload(add(_signature, 0x41)), 0xFF)
        }
        if (v < 27) v += 27;

        bytes32 msgHash = keccak256(abi.encodePacked(_account, schedule-period));

        _verify(_account, ecrecover(msgHash, v, r, s));
    }
    function lockProofOfPersonhood() public scheduler {
        require(proofOfPersonhood[schedule][msg.sender] == 0 && balanceOf[schedule][2][msg.sender] >= 1);
        balanceOf[schedule][2][msg.sender]--;
        population[schedule]++;
        proofOfPersonhood[schedule][msg.sender] = population[schedule];
        personhoodIndex[schedule][population[schedule]] = msg.sender;
    }
    function transferPersonhoodKey(address _to) public scheduler {
        require(proofOfPersonhood[schedule][_to] == 0 && _to != msg.sender);
        proofOfPersonhood[schedule][_to] = proofOfPersonhood[schedule][msg.sender];
        personhoodIndex[schedule][proofOfPersonhood[schedule][msg.sender]] = _to;
        delete proofOfPersonhood[schedule][msg.sender];
    }
    function _transfer(address _from, address _to, uint _value, uint _token) internal { 
        require(balanceOf[schedule][_token][_from] >= _value);
        balanceOf[schedule][_token][_from] -= _value;
        balanceOf[schedule][_token][_to] += _value;        
    }        
    function transfer(address _to, uint _value, uint _token) public scheduler { 
        _transfer(msg.sender, _to, _value, _token);      
    }    
    function approve(address _spender, uint _value, uint _token) public scheduler {
        allowed[schedule][_token][msg.sender][_spender] = _value;
    }
    function transferFrom(address _from, address _to, uint _value, uint _token) public scheduler {
        require(allowed[schedule][_token][_from][msg.sender] >= _value);
        _transfer(_from, _to, _value, _token);
        allowed[schedule][_token][_from][msg.sender] -= _value;
    }
}
