import consoled;
import core.sys.posix.sys.stat;
import dlib.filesystem.filesystem;
import dlib.filesystem.local;
import git.repository;
import git.status;
import git.exception;
import std.algorithm.sorting;
import std.algorithm;
import std.array;
import std.datetime;
import std.file : exists, isFile;
import std.getopt;
import std.path;
import std.stdio;
import std.string;
import std.traits;

static string DEFAULT_COLUMNS = "GdDo_h_n";

enum SortOrder { byName, dirsFirst }

bool sortByName(DirEntry a, DirEntry b) {
  return a.name < b.name;
}

bool sortByNameDirsFirst(DirEntry a, DirEntry b) {
  if (a.isDirectory) {
    if (b.isDirectory) {
      return a.name < b.name;
    } else {
      return true;
    }
  } else {
    if (b.isDirectory) {
      return false;
    } else {
      return a.name < b.name;
    }
  }
}

class Column {
  void write(DirEntry entry, stat_t* fileStats) {}
}
class NameColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(entry.name);
    writec(entry.isDirectory ? "/" : "");
  }
}
class DirColorColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(entry.isDirectory ? FontStyle.underline : FontStyle.none);
  }
}
class DirMarkerColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(entry.isDirectory ? "d" : ".");
  }
}
class ByteSizeColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    auto size = fileStat.st_size;
    writec("%10d".format(size));
  }
}
class HumanReadableSizeColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    auto size = fileStat.st_size;
    auto res = format("%3db", size);
    if (res.length <= 4) {
      writec(res);
      return;
    }

    auto s = size / 1024.0;
    res = format("%.1fk", s);
    if (res.length <= 4) {
      writec(res);
      return;
    }

    s = s / 1024.0;
    res = format("%.1fm", s);
    if (res.length <= 4) {
      writec(res);
      return;
    }

    s = s / 1024.0;
    res = format("%.1fg", s);
    writecln(res);
    if (res.length <= 4) {
      writec(res);
      return;
    }
  }
}
class RwxColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    int mode = fileStat.st_mode;
    auto s = "" ~
      ((mode & S_IRUSR) != 0 ? "r" : "-") ~
      ((mode & S_IWUSR) != 0 ? "w" : "-") ~
      ((mode & S_IXUSR) != 0 ? "x" : "-") ~
      ((mode & S_IRGRP) != 0 ? "r" : "-") ~
      ((mode & S_IWGRP) != 0 ? "w" : "-") ~
      ((mode & S_IXGRP) != 0 ? "x" : "-") ~
      ((mode & S_IROTH) != 0 ? "r" : "-") ~
      ((mode & S_IWOTH) != 0 ? "w" : "-") ~
      ((mode & S_IXOTH) != 0 ? "x" : "-");
    writec(s);
  }
}
class OctalColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    int mode = fileStat.st_mode;
    writec(format("%3o", mode & 0b111_111_111));
  }
}
class ModificationTimeColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    auto dt = SysTime.fromUnixTime(fileStat.st_mtime);
    writec(" ", dt.toISOString(), " ");
  }
}
class SpaceColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(" ");
  }
}
class GitColumn : Column {
  private bool searched = false;
  private bool found = false;
  private GitRepo repo;
  override void write(DirEntry entry, stat_t* fileStat) {
    if (!searched) {
      this.searched = true;
      auto repoPath = discoverRepo(".");
      if (repoPath) {
        repo = openRepository(repoPath);
        found = true;
      }
    }
    if (found) {
      try {
        withRepo(repo, entry, fileStat);
        return;
      } catch (GitException e) {
      }
    }
    withoutRepo(entry, fileStat);
  }
  protected void withRepo(GitRepo repo, DirEntry entry, stat_t* fileStat) {
  }
  protected void withoutRepo(DirEntry entry, stat_t* fileStat) {
  }
}
class GitColorColumn : GitColumn {
  import deimos.git2.status;
  override protected void withRepo(GitRepo repo, DirEntry entry, stat_t* fileStat) {
    auto status = repo.status(entry.name).status;
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
  override protected void withoutRepo(DirEntry entry, stat_t* fileStat) {
    writec(Fg.initial, Bg.initial);
  }
}
class GitStatusColumn : GitColumn {
  import deimos.git2.status;
  override protected void withRepo(GitRepo repo, DirEntry entry, stat_t* fileStat) {
    auto status = repo.status(entry.name).status;
    writec(toString(status));
  }
  override protected void withoutRepo(DirEntry entry, stat_t* fileStat) {
    writec("  ");
  }
  private string toString(git_status_t status) {
    dchar index = '-';
    dchar workTree = '-';
    if (status == GIT_STATUS_CURRENT) {
    }

    if (status == GIT_STATUS_INDEX_NEW) {
      index = 'N';
    }
    if (status == GIT_STATUS_INDEX_MODIFIED) {
      index = 'M';
    }
    if (status == GIT_STATUS_INDEX_DELETED) {
      index = 'D';
    }
    if (status == GIT_STATUS_INDEX_RENAMED) {
      index = 'R';
    }
    if (status == GIT_STATUS_INDEX_TYPECHANGE) {
      index = 'T';
    }

    if (status == GIT_STATUS_WT_NEW) {
      workTree = 'N';
    }
    if (status == GIT_STATUS_WT_MODIFIED) {
      workTree = 'M';
    }
    if (status == GIT_STATUS_WT_DELETED) {
      workTree = 'D';
    }
    if (status == GIT_STATUS_WT_TYPECHANGE) {
      workTree = 'T';
    }
    if (status == GIT_STATUS_WT_RENAMED) {
      workTree = 'R';
    }

    if (status == GIT_STATUS_IGNORED) {
      index = '-';
      workTree = '-';
    }
    return format("%s%s", index, workTree);
  }
}

struct Formatter(T) {
  T columns;

  public this(T columns) {
    this.columns = columns;
  }
  public void write(string path, DirEntry entry) {
    foreach (Column column; columns) {
      stat_t fileStats;
      auto res = stat((path ~ "/" ~ entry.name).toStringz, &fileStats);
      column.write(entry, &fileStats);
    }
    writecln(Fg.initial, Bg.initial);
  }
}

public Formatter!(T) getFormatter(T)(T columns) {
  return Formatter!(T)(columns);
}

class Columns {
  Column[dchar] columns;
  this() {
    columns = [
      'D': new DirMarkerColumn(),
      'G': new GitColorColumn(),
      '_': new SpaceColumn(),
      'b': new ByteSizeColumn(),
      'd': new DirColorColumn(),
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
  return [ EnumMembers!SortOrder ].map!("format(\"  %s\", a)").array.join("\n");
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
  auto formatter = getFormatter(columns);

  path = absolutePath(path);
  path = asNormalizedPath(path).array;
  if (!exists(path)) {
    stderr.writeln("Path does not exists: ", path);
    return 1;
  } else if (isFile(path)) {
    formatter.write(dirName(path), DirEntry(baseName(path), true,false));
    return 0;
  }

  auto dir = openDir(path);

  auto sortFunction = &sortByName;
  if (sort == SortOrder.dirsFirst) {
    sortFunction = &sortByNameDirsFirst;
  }
  auto contents = dir.contents.array.sort!(sortFunction);

  foreach (file; contents) {
    formatter.write(path, file);
  }

  return 0;
}
