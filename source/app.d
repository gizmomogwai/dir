import consoled;
import core.sys.posix.sys.stat;
import dlib.filesystem.filesystem;
import dlib.filesystem.local;
import std.algorithm.sorting;
import std.array;
import std.datetime;
import std.file : exists, isFile;
import std.getopt;
import std.path;
import std.stdio;
import std.string;

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

interface Column {
  void write(DirEntry entry, stat_t* fileStats);
}
class NameColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(entry.name);
  }
}
class DirColorColumn : Column {
  override void write(DirEntry entry, stat_t* fileStat) {
    writec(entry.isDirectory ? FontStyle.bold : FontStyle.none, entry.isDirectory ? "d" : ".");
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
    writeln(res);
    if (res.length <= 4) {
      writec(res);
      return;
    }

  }
}

class RWXColumn : Column {
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
    writec(format("%4o", mode & 0b111_111_111));
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
  private bool searched;
  override void write(DirEntry entry, stat_t* fileStat) {
  }
}
struct Formatter {
  Column[] columns;
  public this(Column[] columns) {
    this.columns = columns;
  }
  public void write(string path, DirEntry entry) {
    foreach (column; columns) {
      stat_t fileStats;
      auto res = stat((path ~ "/" ~ entry.name).toStringz, &fileStats);
      column.write(entry, &fileStats);
    }
    writeln();
  }
}

int main2(string[] args) {
  Column[] columns;
  void columnsHandler(string option, string value) {
    foreach (c; value) {
      switch (c) {
      case 'd':
        columns ~= new DirColorColumn();
        break;
      case 'f':
        columns ~= new RWXColumn();
        break;
      case 'o':
        columns ~= new OctalColumn();
        break;
      case 'h':
        columns ~= new HumanReadableSizeColumn();
        break;
      case 'b':
        columns ~= new ByteSizeColumn();
        break;
      case 's':
        columns ~= new SpaceColumn();
        break;
      case 'm':
        columns ~= new ModificationTimeColumn();
        break;
      case 'n':
        columns ~= new NameColumn();
        break;
      case 'g':
        columns ~= new GitColumn();
        break;
      default:
        throw new Exception("unknown option " ~ c);
      }
    }
  }

  SortOrder sort;
  auto helpInformation = getopt(args,
                                "columns|c", "Specify columns", &columnsHandler,
                                "sort|s", "Sort mode", &sort,
  );
  if (helpInformation.helpWanted) {
    defaultGetoptPrinter("listing files flexible.",
                         helpInformation.options);
    return 0;
  }

  string path = ".";
  if (args.length == 2) {
    path = args[1];
  }

  Formatter formatter = Formatter(columns);

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


import std.stdio : writeln;
import std.string : toStringz;

import core.memory : GC;

import deimos.git2.buffer;
import deimos.git2.types;
import deimos.git2.repository;
import git.repository;
import git.oid;
import git.commit;
import git.status;

void main() {
  /*    git_repository *repo;

    git_buf buffer;
    writeln(git_repository_discover(&buffer, ".".toStringz, cast(bool)true, null));
    auto repoPath = fromStringz(buffer.ptr);
    git_buf_free(&buffer);
    writeln("lowlevel: ", repoPath);
  */
    auto repoPath = discoverRepo(".");
    auto repo = openRepository(repoPath);
    writeln(repo.head());
    writeln(repo.state());


    auto oid = GitOid("4ee7f63c84bda260b6c61780ab11a229a9721d19");
    writeln(oid);
    auto commit = repo.lookupCommit(oid);
    writeln(commit);
    writeln(commit.message);
    writeln(repo.status("source/app.d"));

    foreach (refName, remoteURL, oid, isMerge; repo.walkFetchHead) {
      writeln(refName);
      writeln(remoteURL);
    }

    //writeln("lowlevel: ", git_repository_open(&repo, repoPath.toStringz()));
    //writeln(buffer);
    //git_repository_free(repo);

    //    writeln(discoverRepo("."));
    writeln("END");
}
