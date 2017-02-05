import consoled;
import core.sys.posix.sys.stat;
import git.exception;
import git.repository;
import git.status;
import std.algorithm.sorting;
import std.algorithm;
import std.array;
import std.datetime;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import std.string;
import std.traits;

static string DEFAULT_COLUMNS = "GDdo_f_h_n";

enum SortOrder { byName, dirsFirst }

bool sortByName(DirEntry a, DirEntry b) {
  return a.name < b.name;
}

bool sortByNameDirsFirst(DirEntry a, DirEntry b) {
  if (a.isDir) {
    if (b.isDir) {
      return a.name < b.name;
    } else {
      return true;
    }
  } else {
    if (b.isDir) {
      return false;
    } else {
      return a.name < b.name;
    }
  }
}

class Column {
  void write(DirEntry entry, string absoluteFileName, stat_t* fileStats) {}
}
class NameColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(entry.name.baseName);
    writec(entry.isDir ? "/" : "");
  }
}
class DirColorColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(entry.isDir ? FontStyle.underline : FontStyle.none);
  }
}
class DirMarkerColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(entry.isDir ? "d" : ".");
  }
}
class ByteSizeColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    auto size = fileStat.st_size;
    writec("%10d".format(size));
  }
}
class HumanReadableSizeColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    auto size = fileStat.st_size;
    auto res = format("%3db", size);
    if (res.length <= 4) {
      writec(res);
      return;
    }

    auto sizes = ["k", "m", "g", "t", "p", "e", "z", "y"];
    int current = 0;
    double dSize = size;
    while (current < sizes.length) {
      dSize = dSize / 1024.0;
      res = format("%.1f%s", dSize, sizes[current]);
      if (res.length <= 4) {
        writec(res);
        return;
      }
      res = format("%3.0f%s", dSize, sizes[current]);
      if (res.length <= 4) {
        writec(res);
        return;
      }
      current++;
    }
    throw new Exception("could not format size: %s".format(fileStat.st_size));
  }
}
import std.typecons;
alias Flag = Tuple!(int, "bitmask", string, "name", );
auto PERMISSIONS = [
  Flag(S_IRUSR, "r"),
  Flag(S_IWUSR, "w"),
  Flag(S_IXUSR, "x"),
  Flag(S_IRGRP, "r"),
  Flag(S_IWGRP, "w"),
  Flag(S_IXGRP, "x"),
  Flag(S_IROTH, "r"),
  Flag(S_IWOTH, "w"),
  Flag(S_IXOTH, "x")
];

class RwxColumn : Column {
  private string flag(int mode, Flag f) {
    return (mode & f.bitmask) != 0 ? f.name : "-";
  }
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    int mode = fileStat.st_mode;
    auto s = PERMISSIONS.map!((f)  {return flag(mode, f);}).join("");
    writec(s);
  }
}
class OctalColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    int mode = fileStat.st_mode;
    writec(format("%3o", mode & 0b111_111_111));
  }
}
class ModificationTimeColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    auto dt = SysTime.fromUnixTime(fileStat.st_mtime);
    writec(" ", dt.toISOString(), " ");
  }
}
class SpaceColumn : Column {
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(" ");
  }
}
class GitColumn : Column {
  private bool searched = false;
  private bool found = false;
  private GitRepo repo;
  this() {
    libGitInit();
  }
  ~this() {
    //libGitShutdown(); // crashes when using libgit2 from homebrew
  }
  override void write(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    if (!searched) {
      this.searched = true;
      auto repoPath = discoverRepo(dirName(absoluteFileName));
      if (repoPath) {
        repo = openRepository(repoPath);
        found = true;
      }
    }
    if (found) {
      string workTreeRoot = repo.path.replace(".git/", "");
      try {
        withRepo(repo, workTreeRoot, entry, absoluteFileName, fileStat);
        return;
      } catch (GitException e) {
        // writeln(e);
      }
    }
    withoutRepo(entry, absoluteFileName, fileStat);
  }
  protected void withRepo(GitRepo repo, string workTreeRoot, DirEntry entry, string absoluteFileName, stat_t* fileStat) {
  }
  protected void withoutRepo(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
  }
}
class GitColorColumn : GitColumn {
  import deimos.git2.status;
  override protected void withRepo(GitRepo repo, string workTreeRoot, DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    auto h = absoluteFileName.replace(workTreeRoot, "");
    auto status = repo.status(h).status;
    if (status & GIT_STATUS_IGNORED) {
      writec(Fg.gray);
    } else {
      writec(Fg.initial);
    }
    if ((status & GIT_STATUS_INDEX_NEW) ||
        (status & GIT_STATUS_INDEX_MODIFIED) ||
        (status & GIT_STATUS_INDEX_DELETED) ||
        (status & GIT_STATUS_INDEX_RENAMED) ||
        (status & GIT_STATUS_INDEX_TYPECHANGE)) {
      writec(Bg.lightGreen, Fg.black);
    } else {
      if ((status & GIT_STATUS_WT_NEW) ||
          (status & GIT_STATUS_WT_MODIFIED) ||
          (status & GIT_STATUS_WT_DELETED) ||
          (status & GIT_STATUS_WT_TYPECHANGE) ||
          (status & GIT_STATUS_WT_RENAMED)) {
        writec(Bg.lightRed, Fg.black);
      } else {
        writec(Bg.initial);
      }
    }
  }
  override protected void withoutRepo(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(Fg.initial, Bg.initial);
  }
}
class GitStatusColumn : GitColumn {
  import deimos.git2.status;
  char[git_status_t] status2Index;
  char[git_status_t] status2Worktree;
  this() {
      status2Index = [
        GIT_STATUS_CURRENT: '-',
        GIT_STATUS_INDEX_NEW: 'N',
        GIT_STATUS_INDEX_DELETED: 'D',
        GIT_STATUS_INDEX_MODIFIED: 'M',
        GIT_STATUS_INDEX_RENAMED: 'R',
        GIT_STATUS_INDEX_TYPECHANGE: 'T',
        GIT_STATUS_IGNORED: 'I'
      ];
      status2Worktree = [
        GIT_STATUS_CURRENT: '-',
        GIT_STATUS_WT_NEW: 'N',
        GIT_STATUS_WT_MODIFIED: 'M',
        GIT_STATUS_WT_DELETED: 'D',
        GIT_STATUS_WT_TYPECHANGE: 'T',
        GIT_STATUS_WT_RENAMED: 'R',
        GIT_STATUS_IGNORED: 'I'
      ];
  }
  override protected void withRepo(GitRepo repo, string workTreeRoot, DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec(toString(repo.status(entry.name).status));
  }
  override protected void withoutRepo(DirEntry entry, string absoluteFileName, stat_t* fileStat) {
    writec("  ");
  }
  private string toString(git_status_t status) {
    dchar index = status in status2Index ? status2Index[status] : '-';
    dchar workTree = status in status2Worktree ? status2Worktree[status] : '-';
    return format("%s%s", index, workTree);
  }
}

struct Formatter(T) {
  T columns;
  public this(T columns) {
    this.columns = columns;
  }
  public void write(string path, DirEntry entry) {
    auto absoluteFileName = entry.name;
    stat_t fileStats;
    auto res = stat(absoluteFileName.toStringz, &fileStats);
    foreach (Column column; columns) {
      column.write(entry, absoluteFileName, &fileStats);
    }
    writecln(Fg.initial, Bg.initial, FontStyle.none);
  }
}

public auto createFormatter(T)(T columns) {
  return Formatter!(T)(columns);
}

class Columns {
  Column[dchar] columns;
  this() {
    columns = [
      'D': new DirColorColumn(),
      'G': new GitColorColumn(),
      '_': new SpaceColumn(),
      'b': new ByteSizeColumn(),
      'd': new DirMarkerColumn(),
      'f': new RwxColumn(),
      'h': new HumanReadableSizeColumn(),
      'm': new ModificationTimeColumn(),
      'n': new NameColumn(),
      'o': new OctalColumn(),
      'g': new GitStatusColumn()
    ];
  }
  Column by(dchar c) {
    if (c in columns) {
      return columns[c];
    }
    throw new Exception(format("unknown option %c", c));
  }
  override string toString() {
    return columns.
      byKeyValue().
      map!("format(\"  %s - %s\", a.key, a.value.classinfo)").
      join("\n");
  }
}

auto sortModeDescription() {
  return [EnumMembers!SortOrder].map!("format(\"  %s\", a)").array.join("\n");
}

int main(string[] args) {
  Columns availableColumns = new Columns();
  SortOrder sort = SortOrder.dirsFirst;
  string columnsString = DEFAULT_COLUMNS;
  auto helpInformation =
    getopt(args,
           "columns|c", format("Columns: (default: '%s')\n%s", DEFAULT_COLUMNS, availableColumns.toString()), &columnsString,
           "sort|s", "SortOrder: (default: 'dirsFirst')\n" ~ sortModeDescription(), &sort,
    );

  if (helpInformation.helpWanted) {
    defaultGetoptPrinter("listing files flexible.",
                         helpInformation.options);
    return 0;
  }

  auto path = ".";
  if (args.length == 2) {
    path = args[1];
  }

  auto columns = columnsString.map!((id) {return availableColumns.by(id);}).array;
  auto formatter = createFormatter(columns);

  path = absolutePath(path);
  path = asNormalizedPath(path).array;
  if (!exists(path)) {
    stderr.writeln("Path does not exists: ", path);
    return 1;
  } else if (isFile(path)) {
    formatter.write(dirName(path), DirEntry(baseName(path)));
    return 0;
  }

  auto dir = dirEntries(path, SpanMode.shallow);
  auto sortFunction = &sortByName;
  if (sort == SortOrder.dirsFirst) {
    sortFunction = &sortByNameDirsFirst;
  }
  auto contents = dir.array.sort!(sortFunction);
  foreach (file; contents) {
    formatter.write(path, file);
  }

  return 0;
}
