# Some useful scripts

These are some of my scripts I use on my daily basis. Some of them are simple Ruby 💎 scripts or bash scripts made to simplify time-consuming or boring tasks.

## Scripts list

**[MissingLocalizables](MissingLocalizables)** - to check if localizables have no duplicates, missing keys and so on.

```sh
ruby Src/missing-localizables.rb <path/to/localizables> <base-lang>
```

**[ListSearch](ListSearch)** - to check which elements of the list are found in a directory's contents.

```sh
ruby Src/list-search.rb <path/to/list> <path/to/directory>
```

**[RomsFilter](RomsFilter)** - copy filtered stabile NES roms into a subdirectory.

```sh
./RomsFilter/roms-filter.py <path/to/roms>
```

**[XcodeCleanup](XcodeCleanup)** - to cleanup common Xcode paths.
