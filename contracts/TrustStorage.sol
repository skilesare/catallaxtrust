pragma solidity ^0.4.15;

 contract TrustStorage {

        //keep track of if we have seen this key before or not
        mapping(bytes32 => bool) public genericStoreExists;

        //a place to put our data
        mapping(bytes32 => bytes32) public genericStore;

        mapping(address => bool) public owners;

        //a place to keep track of our keys.  Out of order...but still, we
        //have them
        bytes32[] public genericIterator;

        //keep track of the number of keys we are storing
        uint256 public genericCount;

        address owner;

        /**
        * @dev Throws if called by any account other than the owner.
        */
        modifier onlyOwner() {
            bool test = owners[msg.sender];
            address mmhu = msg.sender;
          require(owners[msg.sender] == true);
          _;
        }

        function TrustStorage(){
          owners[msg.sender] = true;
        }

        function UpdateOwner(address _owner, bool _value) onlyOwner returns (bool){
          owners[_owner] = _value;
          return true;
        }


        //store our data
        // We assume that your variable name has been convered to
        // bytes32.  You can do this via a keccak or converting string to bytes
        // We assume you have keccaked your variable path
        // We assume that all values are cast to bytes32
        function putValue(bytes32 _dataGroup, bytes32 _kecKey, bytes32 _value) returns(bool){

            bytes32 key = keccak256(_dataGroup, _kecKey);
            putValueRaw(key, _value);
            return true;
        }

        function putValueRaw(bytes32 key, bytes32 _value) onlyOwner returns(bool){
            genericStore[key] = _value;
            if(genericStoreExists[key] == false){
                genericStoreExists[key] = true;
                genericIterator.push(key);
                genericCount = genericCount + 1;
            }
            return true;
        }


        //get integers
        function getInt(bytes32 _dataGroup, bytes32 _kecKey) constant returns(uint256){
            bytes32 key = keccak256(_dataGroup, _kecKey);
            return uint256(genericStore[key]);
        }
    }
