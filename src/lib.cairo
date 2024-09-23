use core::starknet::ContractAddress;

#[starknet::interface]
trait IBookStore<TContractState> {
    fn add_book(
        ref self: TContractState,
        name: felt252,
        tags: Array<felt252>,
        description: felt252,
        author: felt252,
        contract_address: ContractAddress,
        price: felt252,
        genre: MBookStore::Genre
    );
    fn get_books_by_author(self: @TContractState, author: felt252) -> Array<MBookStore::BookEntity>;
    fn get_book_by_address(self: @TContractState, address: ContractAddress) -> MBookStore::BookEntity;
    fn get_book_by_tags(self: @TContractState, tags: Array<felt252>) -> Array<MBookStore::BookEntity>;
    fn get_books_by_genre(self: @TContractState, genre: MBookStore::Genre) -> Array<MBookStore::BookEntity>;
    fn edit_book_metadata(
        ref self: TContractState, contract_address: ContractAddress, metadata: MBookStore::Metadata
    );
    // fn get
    // get book by genre
    // add get book by price range?
    fn discard_book(self: @TContractState, contract_address: ContractAddress) -> bool;
}

#[starknet::contract]
mod MBookStore {
    use core::num::traits::Zero;
    use core::starknet::{ContractAddress, get_caller_address};
    use core::starknet::storage::{
        Map, StoragePathEntry, Vec, StoragePointerReadAccess, VecTrait, MutableVecTrait,
        StoragePointerWriteAccess
    };
    use super::IBookStore;

    // ---------------------------------------------------------------------------------------------------------------------

    #[storage]
    struct Storage {
        book: Map<felt252, Vec<ContractAddress>>,
        saved_books: Map<ContractAddress, BookEntity>,
        book_entities: Vec<BookEntity>,
        owner: BookKeeper,
        total_books: u128,
        tags: Vec<felt252>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StoredBook: StoredBook
    }

    #[derive(Drop, starknet::Event)]
    struct StoredBook {
        #[key]
        contract_address: ContractAddress,
        name: felt252,
        price: felt252
    }

    // TODO: Create an Enum of genre and add to the metadata class
    // TODO: Create a metadata class too

    #[derive(Drop, Serde, starknet::Store)]
    struct BookKeeper {
        address: ContractAddress,
        name: felt252
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct Metadata {
        description: felt252,
        genre: Genre
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct BookEntity {
        book: Book,
        price: felt252,
        metadata: Metadata
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct Book {
        contract_address: ContractAddress,
        name: felt252,
        author: felt252,
        date_added: u64
    }

    #[derive(Copy, Drop, PartialEq, Serde, starknet::Store)]
    pub enum Genre {
        Horror,
        Romance,
        Comedy,
        Action
    }

    /// Constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner: BookKeeper) {
        self.owner.write(owner);
        self.total_books.write(0);
    }


    // ------------------------------------------ External functions --------------------------------------------


    // TODO: Implement both external and internal functions here
    #[abi(embed_v0)]
    impl BookStoreImpl of IBookStore<ContractState> {
        fn add_book(
            ref self: ContractState,
            name: felt252,
            tags: Array<felt252>,
            description: felt252,
            author: felt252,
            contract_address: ContractAddress,
            price: felt252,
            genre: Genre
        ) {
            self.assert_ownership();
            self._store_book(name, tags, description, author, contract_address, price, genre);
        }

        fn get_books_by_author(self: @ContractState, author: felt252) -> Array<BookEntity> {
            let mut books: Array<BookEntity> = array![];
            for i in 0..self.book_entities.len() {
                let mut book_entity: BookEntity = self.book_entities.at(i).read();
                if author == book_entity.book.name {
                    books.append(book_entity)
                }
            };
            books
        }

        fn get_book_by_address(self: @ContractState, address: ContractAddress) -> BookEntity {
            self.saved_books.entry(address).read()
        } 

        fn get_books_by_genre(self: @ContractState, genre: Genre) -> Array<BookEntity> {
            let mut books: Array<BookEntity> = array![];
            for i in 0..self.book_entities.len() {
                let mut book_entity: BookEntity = self.book_entities.at(i).read();
                if genre == book_entity.metadata.genre {
                    books.append(book_entity);
                }
            };
            books
        }

        fn get_book_by_tags(self: @ContractState, tags: Array<felt252>) -> Array<BookEntity> {
            let mut books: Array<BookEntity> = array![];

            // Check book, and then saved_books. Note that book is a Map<felt252, Vec<CA>> and
            // saved_books is of Map<CA, BookEntity>. We need the CA from book for saved_books
            for tag in tags {
                for i in 0..self.book.entry(tag).len() {
                    let mut contract_address: ContractAddress = self.book.entry(tag).at(i).read();
                    let mut book_entity: BookEntity = self.saved_books.entry(contract_address).read();
                    books.append(book_entity);
                };
            };
            books
        }

        fn edit_book_metadata(
            ref self: ContractState, contract_address: ContractAddress, metadata: Metadata
        ) {
            self.assert_ownership();
            self.saved_books.entry(contract_address).metadata.write(metadata);
        }

        fn discard_book(self: @ContractState, contract_address: ContractAddress) -> bool {
            self.assert_ownership();
            // TODO: Implement delete
            true
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _store_book(ref self: ContractState, name: felt252, tags: Array<felt252>, description: felt252, author: felt252,
                        contract_address: ContractAddress, price: felt252, genre: Genre) {
            // here, after adding the book, increase the book count by 1 and emit the added book.
            // for the array of tags passed here, if total books == 0, write direct, else find the tags if they already exist
            // and load the contract address of the book for each tag there, respectively.
            
            let mut total_books: u128 = self.total_books.read();

            // Confirm if there isn't already an entry like this in saved_books
            // if total_books != 0 {
            //     assert(self.saved_books.entry(contract_address).read() == Book, "Book with that address already exists.");
            // }

            // Save the book
            let metadata = Metadata { description, genre };
            let book = Book { contract_address, name, author, date_added: starknet::get_block_timestamp() };
            let mut book_entity = BookEntity { book, price, metadata };
            let mut book_entity_ref = @book_entity;
            self.saved_books.entry(contract_address).write(book_entity);
            self.book_entities.append().write(*book_entity_ref);
            // Add all tags to the Map, and fill the tags keys with this one particular book contract address
            // Save the book first before entering into this block
            // for each tag in tags, add the contract address in the Vec
            let tags_2 = @tags;
            for tag in tags {
                self.book.entry(tag).append().write(contract_address);
            };

            // Write tags.
            for i in 0..tags_2.len() {
                let mut check_match: bool = false;
                let mut value_1: felt252 = *tags_2.at(i);
                for j in 0..self.tags.len() {
                    let mut value_2: felt252 = self.tags.at(j).read();
                    if value_1 == value_2 {
                        check_match = true;
                        break;
                    }
                };

                if check_match == false {
                    self.tags.append().write(value_1);
                }
            };
            
            self.total_books.write(total_books + 1);
            self.emit( StoredBook { contract_address, name, price } );
        }

        fn assert_ownership(self: @ContractState) {
            let owner: ContractAddress = self.owner.address.read();
            let caller: ContractAddress = get_caller_address();
            assert(!caller.is_zero(), 'Caller address is Zero');
            assert(caller == owner, 'Unauthorized Operation.');
        }
    }

    #[external(v0)]
    fn get_available_tags_and_genres(self: @ContractState) -> Array<felt252> {
        // let mut (tags, genres): (Array<felt252>, Array<felt252>) = (array![], array![]);
        let mut tags_and_genres: Array<felt252> = array![];
        tags_and_genres.append('tags');
        for i in 0..self.tags.len() {
            tags_and_genres.append(self.tags.at(i).read());
        }

        // tags_and_genres.append(Genre::Horror);
        // tags_and_genres.append(Genre::Romance);
        // tags_and_genres.append(Genre::Comedy);
        // tags_and_genres.append(Genre::Action);
        // (tags, genres)
        tags_and_genres
    }
}
