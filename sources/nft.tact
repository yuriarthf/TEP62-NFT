// ------------------ Structures ------------------ //
struct ItemMetadata {
  init: Int?;
  index: Int;
  collection_address: Address;
  owner_address: Address;
  individual_content: Cell;
}

struct CollectionMetadata {
  next_item_index: Int;
  collection_content: Cell;
  owner_address: Address;
}

// ------------------ Internal Messages ------------------ //
message Initialize {
  query_id: Int as uint64;
  owner_address: Address;
  collection_owner: Address;
  forward_payload: Slice | Cell as notification;
}

message Minted {
  query_id: Int as uint64;
  forward_payload: Slice | Cell as notification;
}

message Transfer(0x5fcc3d14) {
  query_id: Int as uint64;
  new_owner: Address;
  response_destinaton: Address;
  custom_payload: Cell?;
  forward_amount: Int as grams;
  forward_payload: Slice | Cell as notification;
}

message OwnershipAssigned(0x05138d91) {
  query_id: Int as uint64;
  prev_owner: Address;
  forward_payload: Slice | Cell as notification;
}

message GetStaticData(0x2fcb26a2) {
  query_id: Int as uint64;
}

message Excesses(0xd53276db) {
  query_id: Int as uint64;
}

message ReportStaticData(0x8b771735) {
  query_id: Int as uint64;
  index: Int as uint256;
  collection: Address;
}

message Mint {
  query_id: Int as uint64;
  recipient: Address;
  individual_content: Cell;
  forward_payload: Slice | Cell as notification;
}

message MintExcesses {
  query_id: Int as uint64;
  message: String;
}

contract NFTItem {

  const minTonsForStorage: Int = ton("0.01");
  const gasConsumption: Int = ton("0.01");

  index: Int as uint256;
  owner: Address;
  collection: Address;
  individualContent: Cell;

  init(
    index: Int,
    collection: Address,
    individualContent: Cell
  ) {
    this.index = index;
    this.collection = collection;
    this.individualContent = individualContent;
  }

  receive(msg: Initialize) {
    let ctx: Context = context();
    require(ctx.sender == this.collection, "Only Collection");

    let fwdFee = ctx.readForwardFee();
    let minTxDebit = fwdFee + 2 * this.gasConsumption + this.minTonsForStorage;
    require(ctx.value > minTxDebit, "Invalid value");

    this.owner = msg.owner_address;

    send(SendParameters{
      to: msg.owner_address,
      body: Minted{
        query_id: msg.query_id,
        forward_payload: msg.forward_payload
      }.toCell()
    });
    
    let remainder: Int = ctx.value - minTxDebit;
    if (remainder - fwdFee > 0) {
      send(SendParameters{
        to: msg.collection_owner,
        mode: SendRemaining,
        body: MintExcesses{
          query_id: msg.query_id,
          message: "Excesses from Mint"
        }.toCell()
      });
    }
  }

  receive(msg: Transfer) {
    let ctx: Context = context();
    require(ctx.sender == self.owner, "Only Owner");
    require(ctx.value >= forward_amount + ton("1"), "Invalid value");

    if (msg.forward_amount > 0) {
      send(SendParameters{
        to: msg.new_owner,
        value: forward_amount,
        body: OwnershipAssigned{
          query_id: msg.query_id,
          forward_payload: msg.forward_payload,
          prev_owner: this.owner
        }.toCell();
      });
    }

    this.owner = msg.new_owner;

    send(SendParameters{
      to: msg.response_destination,
      value: ctx.value - msg.forward_amount,
      mode: SendRemaining + SendIgnoreErrors,
      body: Excesses{query_id: msg.query_id}.toCell()
    });
  }

  receive(msg: GetStaticData) {
    let ctx: Context = context();

    send(SendParameters{
      to: ctx.sender;
      value: 0,
      mode: SendRemaining + SendIgnoreErrors;
      bounce: true,
      body: ReportStaticData{
        query_id: msg.query_id,
        index: this.context,
        collection: this.collection
      }.toCell()
    });
  }

  bounced(msg: Slice) {
    // TODO: Handle
  }

  get fun get_nft_data(): ItemMetadata {
    return ItemMetadata{
      init: 1,
      index: this.index,
      collection_address: this.collection,
      owner_address: this.owner,
      individual_content:  this.individualContent
    };
  }
}

contract NFTCollection {
  owner: Address;
  nextItemIndex: Int;
  collectionContent: Cell;
  totalSupply: Int;

  init(owner: Address, collectionContent: Cell) {
    this.owner = owner;
    this.nextItemIndex = 0;
    this.collectionContent = collectionContent;
    this.totalSupply = 0;
  }

  receive(msg: Mint) {
    let ctx: Context = context();
    require(ctx.sender == this.owner, "Only Owner");
    let stateInit: StateInit = getNftItemInit(this.nextItemIndex, msg.individual_content);
    send(SendParameters{
      to: contractAddress(stateInit),
      mode: SendRemaining,
      body: Initialize{
        query_id: msg.query_id,
        owner_address: msg.recipient,
        collection_owner: this.owner,
        forward_payload: msg.forward_payload
      }.toCell(),
      code: stateInit.code,
      data: stateInit.data
    });

    this.totalSupply += 1;
  }

  fun getNftItemInit(index: Int, individualContent: Cell): StateInit {
    return initOf NFTItem(index, myAddress(), individualContent);
  }

  get fun get_collection_data(): CollectionMetadata {
    return CollectionMetadata{
      next_item_index: this.nextItemIndex,
      collection_content: this.collectionContent,
      owner_address: this.owner
    };
  }

  get fun get_nft_address_by_index(): Address {
    // TODO: Implement
  }

  // TODO: Convert to String
  get fun get_nft_content(int index, cell individual_content): Cell {
    return beginCell(beginParse(this.collectionContent), beginParse(individual_content));
  }
}