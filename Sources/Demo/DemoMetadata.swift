// Generated sample metadata in the /rest/metadata/objects response shape.
enum DemoData {
    static let metadataJSON = #"""
{
 "data": {
  "objects": [
   {
    "id": "111c0e55-1bf7-4706-8aeb-c3ecc2063c21",
    "nameSingular": "person",
    "namePlural": "people",
    "labelSingular": "Person",
    "labelPlural": "People",
    "icon": null,
    "isActive": true,
    "isSystem": false,
    "isCustom": false,
    "labelIdentifierFieldMetadataId": "026772d1-1320-4fee-86d0-d316f6432b51",
    "imageIdentifierFieldMetadataId": null,
    "fields": [
     {
      "id": "026772d1-1320-4fee-86d0-d316f6432b51",
      "type": "FULL_NAME",
      "name": "name",
      "label": "Name",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "e2e0abf4-d6af-4fdc-b8c4-e5f87bef396a",
      "type": "EMAILS",
      "name": "emails",
      "label": "Emails",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "2caf08ea-2488-46aa-9e36-f36dbc71919f",
      "type": "PHONES",
      "name": "phones",
      "label": "Phones",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "2a8e5175-f193-4f1c-93c1-ab8628faa9b9",
      "type": "TEXT",
      "name": "jobTitle",
      "label": "Job Title",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "faa38d57-99d9-4ec5-b226-d459d0e307a5",
      "type": "TEXT",
      "name": "city",
      "label": "City",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "308b01d3-5340-4688-b408-09c3683ab096",
      "type": "LINKS",
      "name": "linkedinLink",
      "label": "Linkedin",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "25686445-0134-4e3e-9db7-377e8d269f25",
      "type": "MULTI_SELECT",
      "name": "tags",
      "label": "Tags",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "0fe6eb0d-ace4-46e3-b3db-ce78351fbeb0",
        "value": "INVESTOR",
        "label": "Investor",
        "color": "green",
        "position": 0
       },
       {
        "id": "95b0d755-5c6a-42e4-9d48-19a3a1dca1af",
        "value": "PARTNER",
        "label": "Partner",
        "color": "blue",
        "position": 1
       },
       {
        "id": "4ceb9a16-ea62-4d82-89cf-1064603c97a5",
        "value": "ADVISOR",
        "label": "Advisor",
        "color": "purple",
        "position": 2
       },
       {
        "id": "d1b5763c-375b-4951-90e3-f41025f901ec",
        "value": "PRESS",
        "label": "Press",
        "color": "orange",
        "position": 3
       },
       {
        "id": "3cacb81d-fdce-4577-8bbb-b6a4ca9d160a",
        "value": "REGULATOR",
        "label": "Regulator",
        "color": "red",
        "position": 4
       },
       {
        "id": "e49f9e6d-2468-4069-bf84-3c53016f4ae3",
        "value": "CUSTOMER",
        "label": "Customer",
        "color": "sky",
        "position": 5
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "23345cbd-6b29-440b-8fa8-15ebbd0a616b",
      "type": "SELECT",
      "name": "stage",
      "label": "Relationship",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "b4352791-5ddc-45ae-93f1-ddd470e7fb18",
        "value": "COLD",
        "label": "Cold",
        "color": "gray",
        "position": 0
       },
       {
        "id": "42c15f4c-d5c2-4904-a181-67f8cf31e6f9",
        "value": "WARM",
        "label": "Warm",
        "color": "yellow",
        "position": 1
       },
       {
        "id": "b5c09cd3-ed1f-4a6a-b233-d7a93c351194",
        "value": "ACTIVE",
        "label": "Active",
        "color": "green",
        "position": 2
       },
       {
        "id": "041bb06f-8166-4c4e-8267-7c0276cc5842",
        "value": "DORMANT",
        "label": "Dormant",
        "color": "red",
        "position": 3
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "c86bf1e6-7f5f-498f-9bf9-9c12f04b85d2",
      "type": "RATING",
      "name": "warmth",
      "label": "Warmth",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "51a740b6-2990-4b63-bf85-51a8da870b22",
      "type": "ARRAY",
      "name": "interests",
      "label": "Interests",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "2676a3aa-193c-43d2-b039-092c7dbed9f3",
      "type": "DATE",
      "name": "lastMet",
      "label": "Last met",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "d68620dd-d918-493f-ae2a-dffe6d0f98a2",
      "type": "RELATION",
      "name": "company",
      "label": "Company",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": {
       "type": "MANY_TO_ONE",
       "targetObjectMetadata": {
        "id": "9eac7907-f7bb-456c-85f5-af1c9f32ef61",
        "nameSingular": "company",
        "namePlural": "companies"
       }
      }
     },
     {
      "id": "8a082e57-4a79-46a8-b95a-0aa30a30cca7",
      "type": "UUID",
      "name": "companyId",
      "label": "Company id",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "de5ba974-b239-4589-9bf2-b885fc949ab1",
      "type": "UUID",
      "name": "id",
      "label": "Id",
      "description": null,
      "icon": null,
      "isNullable": false,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "4b284911-0ccd-4c4e-bbb1-126bd3b4b068",
      "type": "DATE_TIME",
      "name": "createdAt",
      "label": "Creation date",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "6a033bad-c5cb-4e40-b785-becd8e1a95de",
      "type": "DATE_TIME",
      "name": "updatedAt",
      "label": "Last update",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "a9f910b0-16ca-49a8-8aac-518c31b8fab3",
      "type": "DATE_TIME",
      "name": "deletedAt",
      "label": "Deleted at",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "29ef6d89-f5a8-4b42-9443-721b0fec48dd",
      "type": "ACTOR",
      "name": "createdBy",
      "label": "Created by",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "efdf6962-b73c-4cd8-bfd3-d99cf9932f7e",
      "type": "POSITION",
      "name": "position",
      "label": "Position",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "23b6c06a-6886-4f16-ab7d-f416059554da",
      "type": "TS_VECTOR",
      "name": "searchVector",
      "label": "Search vector",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     }
    ]
   },
   {
    "id": "8ba24324-2ee2-4408-9a0c-e7961e8b3a84",
    "nameSingular": "company",
    "namePlural": "companies",
    "labelSingular": "Company",
    "labelPlural": "Companies",
    "icon": null,
    "isActive": true,
    "isSystem": false,
    "isCustom": false,
    "labelIdentifierFieldMetadataId": "21a22b06-844b-49b0-9334-1f04a80f6e60",
    "imageIdentifierFieldMetadataId": null,
    "fields": [
     {
      "id": "21a22b06-844b-49b0-9334-1f04a80f6e60",
      "type": "TEXT",
      "name": "name",
      "label": "Name",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "84df9429-f609-4935-8883-78cb566199df",
      "type": "LINKS",
      "name": "domainName",
      "label": "Website",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": {"type": "domain", "maxNumberOfValues": 1},
      "relation": null
     },
     {
      "id": "3af6f5b6-75cd-4484-bae1-b7e77c7dac29",
      "type": "NUMBER",
      "name": "employees",
      "label": "Employees",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "e1892255-cf12-4e16-9eeb-1411a7a089db",
      "type": "CURRENCY",
      "name": "annualRecurringRevenue",
      "label": "ARR",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "fab83c17-0ff5-4c50-abb7-7e39ff7cd588",
      "type": "ADDRESS",
      "name": "address",
      "label": "Address",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "4dbe65eb-05f9-4ee9-ae73-4e8f23af7cc5",
      "type": "BOOLEAN",
      "name": "idealCustomerProfile",
      "label": "ICP",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "c6cc8cb1-b1ca-454a-9041-921d0834ff7a",
      "type": "MULTI_SELECT",
      "name": "sectors",
      "label": "Sectors",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "9e6eb0f7-08f4-4426-9173-5169f836fe49",
        "value": "FINTECH",
        "label": "Fintech",
        "color": "green",
        "position": 0
       },
       {
        "id": "36c1b19a-d69f-4ba8-a530-cc7aaed29cb5",
        "value": "EXCHANGE",
        "label": "Exchange",
        "color": "turquoise",
        "position": 1
       },
       {
        "id": "bd5320ea-d75c-42c2-94fa-5c400d25f481",
        "value": "BANK",
        "label": "Bank",
        "color": "sky",
        "position": 2
       },
       {
        "id": "ca138c93-cf9d-4a87-8039-2dc863dc3515",
        "value": "CUSTODY",
        "label": "Custody",
        "color": "blue",
        "position": 3
       },
       {
        "id": "c9d0f945-29b4-433e-894f-02a9fd3a766b",
        "value": "PAYMENTS",
        "label": "Payments",
        "color": "purple",
        "position": 4
       },
       {
        "id": "6c3d9e89-ee8b-4a28-b10f-0bfc9f8753b7",
        "value": "DEFI",
        "label": "DeFi",
        "color": "pink",
        "position": 5
       },
       {
        "id": "0a91a72f-24bf-4ae3-a3dc-d65122b336f7",
        "value": "MARKET_MAKER",
        "label": "Market Maker",
        "color": "red",
        "position": 6
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "56b81321-2c84-4b80-b6ac-9bd5a21b27e2",
      "type": "SELECT",
      "name": "tier",
      "label": "Tier",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "2884319e-8d1d-40e4-866a-bbcdf7178e68",
        "value": "TIER_1",
        "label": "Tier 1",
        "color": "purple",
        "position": 0
       },
       {
        "id": "bcd6bf58-596f-4150-9f3a-c16e923afba5",
        "value": "TIER_2",
        "label": "Tier 2",
        "color": "blue",
        "position": 1
       },
       {
        "id": "693dab49-d966-407a-8548-2acff3a49e50",
        "value": "TIER_3",
        "label": "Tier 3",
        "color": "gray",
        "position": 2
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "f-company-account-owner",
      "type": "RELATION",
      "name": "accountOwner",
      "label": "Account Owner",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": {"relationType": "MANY_TO_ONE", "joinColumnName": "accountOwnerId", "onDelete": "SET_NULL"},
      "relation": {
       "type": "MANY_TO_ONE",
       "targetObjectMetadata": {
        "id": "fb0abc4e-e7c2-493f-b3cd-137754e4017f",
        "nameSingular": "workspaceMember",
        "namePlural": "workspaceMembers"
       }
      }
     },
     {
      "id": "f-company-account-owner-id",
      "type": "UUID",
      "name": "accountOwnerId",
      "label": "Account owner id",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "f-company-tag",
      "type": "SELECT",
      "name": "tag",
      "label": "Type",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "cdb380fa-25bf-4ea9-870f-f58733a7668c",
        "value": "INSTITUTIONAL",
        "label": "Institutional",
        "color": "violet",
        "position": 0
       },
       {
        "id": "7801f608-9a68-407f-bc5f-fbfa002e012b",
        "value": "DEFI",
        "label": "DeFI",
        "color": "blue",
        "position": 1
       },
       {
        "id": "d3cd1f03-e193-496a-a461-1396fb846824",
        "value": "REGULATORY",
        "label": "Regulatory",
        "color": "orange",
        "position": 2
       },
       {
        "id": "37c5f3dd-82e7-4971-b5e8-7184d7fd4564",
        "value": "INDUSTRY_GROUPS",
        "label": "Industry Groups",
        "color": "green",
        "position": 3
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "f-company-type",
      "type": "MULTI_SELECT",
      "name": "companyType",
      "label": "Company type",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": true,
      "options": [
       {
        "id": "3751fd04-eced-42ea-81e4-f07f4f233876",
        "value": "EXCHANGE",
        "label": "Exchange",
        "color": "blue",
        "position": 0
       },
       {
        "id": "17601b7f-26a9-4141-aa8e-5bcd3e536617",
        "value": "INSTITUTIONAL_PARTNER",
        "label": "Institutional partner",
        "color": "violet",
        "position": 1
       },
       {
        "id": "8f394638-6121-40b0-bc4b-d5e2354e2034",
        "value": "BANKING_OR_PAYMENT_PROVIDER",
        "label": "Banking or payment provider",
        "color": "cyan",
        "position": 2
       },
       {
        "id": "a48b9ecf-6ee4-4223-b844-2451fb37fc50",
        "value": "MARKET_MAKER",
        "label": "Market maker",
        "color": "green",
        "position": 3
       },
       {
        "id": "89f43f75-eae6-4d49-801c-83d8570f570f",
        "value": "VENDOR",
        "label": "Vendor",
        "color": "gray",
        "position": 4
       },
       {
        "id": "4758c8ff-b3f6-46c6-98dc-babda6a357a5",
        "value": "CARD_PROVIDER",
        "label": "Card Provider",
        "color": "gray",
        "position": 5
       },
       {
        "id": "6ffb984d-a65c-4b0c-99a5-6e0c77b8094d",
        "value": "RWA_INVESTMENT_PLATFORM",
        "label": "RWA Investment Platform",
        "color": "ruby",
        "position": 6
       },
       {
        "id": "ce68ca46-7038-480e-b884-c7b6eb2093c2",
        "value": "TOKENISED_ONCHAIN_STOCKS_ISSUER",
        "label": "Tokenised Onchain Stocks Issuer",
        "color": "gray",
        "position": 7
       },
       {
        "id": "e8f68600-2949-4734-b5e5-46271aeec09d",
        "value": "BLOCKCHAIN_L2",
        "label": "Blockchain/L2",
        "color": "red",
        "position": 8
       },
       {
        "id": "efa74981-89c1-43d4-b8da-44e8bf624cbb",
        "value": "PAYMENTS_INFRA",
        "label": "Payments Infra",
        "color": "orange",
        "position": 9
       },
       {
        "id": "aa83f5eb-26c3-47da-b3d4-65c36a00833e",
        "value": "ONRAMP_WIDGET",
        "label": "Onramp Widget",
        "color": "iris",
        "position": 10
       },
       {
        "id": "a75ce2e2-e3d6-46a8-b78b-6afd19aae4c2",
        "value": "CHAIN_FOUNDATION_TREASURY",
        "label": "Chain Foundation/Treasury",
        "color": "brown",
        "position": 11
       },
       {
        "id": "c92feffd-d0f4-42dd-95e7-42dbc518b159",
        "value": "DEFI_PROTOCOL",
        "label": "Defi Protocol",
        "color": "amber",
        "position": 12
       },
       {
        "id": "12b83b39-9f6a-4bfe-83ac-8a386873a865",
        "value": "LENDING_PROTOCOL",
        "label": "Lending Protocol",
        "color": "red",
        "position": 13
       },
       {
        "id": "96371bde-fb99-4902-9f52-a13ffbfd27b4",
        "value": "TRADFI_RESERVE",
        "label": "TradFi Reserve",
        "color": "red",
        "position": 14
       },
       {
        "id": "6f6e1954-c8e3-4641-b93b-af3732583b22",
        "value": "ALT_STABLE",
        "label": "Alt Stable",
        "color": "bronze",
        "position": 15
       },
       {
        "id": "2ac8c15f-3b96-4005-a3cc-71c38ea0da9d",
        "value": "CUSTODIAN",
        "label": "Custodian",
        "color": "tomato",
        "position": 16
       },
       {
        "id": "4412f189-3f74-4abb-baac-09e20669b77d",
        "value": "COLLATERAL_PRIME_BROKER",
        "label": "Collateral / Prime Broker",
        "color": "gray",
        "position": 17
       },
       {
        "id": "6dc0a8b3-60d9-42b5-9b91-30498ee592ba",
        "value": "INSURANCE",
        "label": "Insurance",
        "color": "iris",
        "position": 18
       },
       {
        "id": "432b89a6-d720-4a0c-8c28-de7a318f6e8f",
        "value": "APP",
        "label": "App",
        "color": "grass",
        "position": 19
       },
       {
        "id": "37dea2e6-2f35-4038-b873-a7d2a40df1ac",
        "value": "ASSET_MANGER",
        "label": "Asset Manger",
        "color": "green",
        "position": 20
       },
       {
        "id": "6fd93d0b-2a3c-4c93-a733-4d96b9063043",
        "value": "BANK",
        "label": "Bank",
        "color": "jade",
        "position": 21
       },
       {
        "id": "058c88de-1434-45ed-9258-683286872ae3",
        "value": "INSTITUTIONAL_INFRASTRUCTURE",
        "label": "Institutional Infrastructure",
        "color": "mint",
        "position": 22
       },
       {
        "id": "d6c2c61b-ecbc-41d3-8902-1c998c474a85",
        "value": "HEDGE_FUNDS",
        "label": "Hedge Funds",
        "color": "tomato",
        "position": 23
       },
       {
        "id": "130dc747-a03f-4eed-ac77-85e4597d449e",
        "value": "CONSULTANTS",
        "label": "Consultants",
        "color": "orange",
        "position": 24
       },
       {
        "id": "e7c6cf10-f4d4-49d7-9f67-b2b355b3211e",
        "value": "PENSION_FUNDS",
        "label": "Pension Funds",
        "color": "amber",
        "position": 25
       },
       {
        "id": "bb97978e-7319-4ce8-8138-d904db15ccf5",
        "value": "RATING_AGENCIES",
        "label": "Rating Agencies",
        "color": "yellow",
        "position": 26
       },
       {
        "id": "d9024d22-dbf2-4791-bc10-2b4f38ecccbb",
        "value": "MERCH",
        "label": "merch",
        "color": "lime",
        "position": 27
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "3e0915c3-8de9-43f4-890e-7880d93b4210",
      "type": "RELATION",
      "name": "people",
      "label": "People",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": {
       "type": "ONE_TO_MANY",
       "targetObjectMetadata": {
        "id": "2012173d-a572-4a39-8101-8eb052ec9537",
        "nameSingular": "person",
        "namePlural": "people"
       },
       "targetFieldMetadata": {
        "id": "f-person-company",
        "name": "company"
       }
      }
     },
     {
      "id": "01db3971-3cfe-4dce-9dcd-b2c53537bb8c",
      "type": "UUID",
      "name": "id",
      "label": "Id",
      "description": null,
      "icon": null,
      "isNullable": false,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "87726d29-88db-4028-b10c-b946202588d6",
      "type": "DATE_TIME",
      "name": "createdAt",
      "label": "Creation date",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "dfd21f86-99e1-4794-9290-34863e99faec",
      "type": "DATE_TIME",
      "name": "updatedAt",
      "label": "Last update",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "da4e3623-b75f-4a62-9037-0a03912b04b9",
      "type": "DATE_TIME",
      "name": "deletedAt",
      "label": "Deleted at",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "42714738-5b11-4b50-9e8c-ad9bd4f2a67c",
      "type": "ACTOR",
      "name": "createdBy",
      "label": "Created by",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "d6d01faa-6ef0-4acb-bfd9-6aa55719f85e",
      "type": "POSITION",
      "name": "position",
      "label": "Position",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "a9083bc2-9e88-4656-b29f-9b6769119b89",
      "type": "TS_VECTOR",
      "name": "searchVector",
      "label": "Search vector",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     }
    ]
   },
   {
    "id": "a20e3b45-1e96-4bcf-ba66-24ebd561d4ac",
    "nameSingular": "opportunity",
    "namePlural": "opportunities",
    "labelSingular": "Opportunity",
    "labelPlural": "Opportunities",
    "icon": null,
    "isActive": true,
    "isSystem": false,
    "isCustom": false,
    "labelIdentifierFieldMetadataId": "356add7c-ffbb-4c7c-a5d7-ee3ca443f034",
    "imageIdentifierFieldMetadataId": null,
    "fields": [
     {
      "id": "356add7c-ffbb-4c7c-a5d7-ee3ca443f034",
      "type": "TEXT",
      "name": "name",
      "label": "Name",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "6336924e-c217-455a-bf1f-c4057ddafce8",
      "type": "CURRENCY",
      "name": "amount",
      "label": "Amount",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "dec36a79-9fec-410e-85ae-b715f20305fc",
      "type": "DATE_TIME",
      "name": "closeDate",
      "label": "Close date",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "44a4383d-978c-46ef-8267-aee0d014f2d1",
      "type": "SELECT",
      "name": "stage",
      "label": "Stage",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": [
       {
        "id": "523e3fb4-9892-4643-abde-c18e94e8caf5",
        "value": "NEW",
        "label": "New",
        "color": "red",
        "position": 0
       },
       {
        "id": "3a110f37-abe9-477e-8915-57f38c0a36c8",
        "value": "SCREENING",
        "label": "Screening",
        "color": "purple",
        "position": 1
       },
       {
        "id": "664a70e0-c083-44d7-b4d0-dfe2696716c9",
        "value": "MEETING",
        "label": "Meeting",
        "color": "sky",
        "position": 2
       },
       {
        "id": "f2f8ba11-62d0-443f-ab23-fd6591b069b9",
        "value": "PROPOSAL",
        "label": "Proposal",
        "color": "turquoise",
        "position": 3
       },
       {
        "id": "2f0cd031-7391-419d-8c48-dc2c41ff4e7f",
        "value": "CUSTOMER",
        "label": "Customer",
        "color": "yellow",
        "position": 4
       }
      ],
      "settings": null,
      "relation": null
     },
     {
      "id": "53af6ffc-601f-47e0-a149-322142147fee",
      "type": "RELATION",
      "name": "company",
      "label": "Company",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": {
       "type": "MANY_TO_ONE",
       "targetObjectMetadata": {
        "id": "8ceab5b8-47c8-4412-8431-4452165c652c",
        "nameSingular": "company",
        "namePlural": "companies"
       }
      }
     },
     {
      "id": "b7dcc039-6c91-4d55-b29c-1893f155b6ad",
      "type": "UUID",
      "name": "companyId",
      "label": "Company id",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "d1555932-3061-4c0b-861a-e3a94aa5ba74",
      "type": "RELATION",
      "name": "pointOfContact",
      "label": "Point of Contact",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": {
       "type": "MANY_TO_ONE",
       "targetObjectMetadata": {
        "id": "1a4b9119-f777-43c6-be1a-bb7b4aac9c91",
        "nameSingular": "person",
        "namePlural": "people"
       }
      }
     },
     {
      "id": "f4f925f6-6cc5-4d5a-a821-c246e55a5a59",
      "type": "UUID",
      "name": "pointOfContactId",
      "label": "Point of contact id",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "b505f890-4354-4b0d-9683-3fda116c3b23",
      "type": "UUID",
      "name": "id",
      "label": "Id",
      "description": null,
      "icon": null,
      "isNullable": false,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "54379bd3-1553-4046-bc1d-6c009aea6f16",
      "type": "DATE_TIME",
      "name": "createdAt",
      "label": "Creation date",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "22bc1e70-6802-4906-bc01-aa7876a94f8d",
      "type": "DATE_TIME",
      "name": "updatedAt",
      "label": "Last update",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "a906988e-bc7e-4bfe-b6cd-98a210aa56e8",
      "type": "DATE_TIME",
      "name": "deletedAt",
      "label": "Deleted at",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "130f437b-2233-4e14-bb48-5b48d5deb8c4",
      "type": "ACTOR",
      "name": "createdBy",
      "label": "Created by",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "8bd50013-52dd-429d-8a76-9d134aad0c5f",
      "type": "POSITION",
      "name": "position",
      "label": "Position",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     },
     {
      "id": "6cced010-429e-4aab-9c81-b6a43baa5450",
      "type": "TS_VECTOR",
      "name": "searchVector",
      "label": "Search vector",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": true,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     }
    ]
   },
   {
    "id": "fb0abc4e-e7c2-493f-b3cd-137754e4017f",
    "nameSingular": "workspaceMember",
    "namePlural": "workspaceMembers",
    "labelSingular": "Workspace Member",
    "labelPlural": "Workspace Members",
    "icon": null,
    "isActive": true,
    "isSystem": true,
    "isCustom": false,
    "labelIdentifierFieldMetadataId": "952fe654-9830-4cb2-afab-3e40a0568f3e",
    "imageIdentifierFieldMetadataId": null,
    "fields": [
     {
      "id": "952fe654-9830-4cb2-afab-3e40a0568f3e",
      "type": "FULL_NAME",
      "name": "name",
      "label": "Name",
      "description": null,
      "icon": null,
      "isNullable": true,
      "isActive": true,
      "isSystem": false,
      "isCustom": false,
      "options": null,
      "settings": null,
      "relation": null
     }
    ]
   }
  ]
 },
 "pageInfo": {
  "hasNextPage": false
 },
 "totalCount": 4
}
"""#
}
