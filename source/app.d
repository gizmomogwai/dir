import std.file : exists;
import std.getopt;
import std.stdio;
import std.string;
import consoled;
import dlib.filesystem.local;
import dlib.filesystem.filesystem;
import std.algorithm.sorting;
import std.array;
import std.path;
import core.sys.posix.sys.stat;

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
import std.datetime;
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

struct Formatter {
  Column[] columns;
  public this(Column[] columns) {
    this.columns = columns;
  }
  public void write(DirEntry entry) {
    foreach (column; columns) {
      stat_t fileStats;
      auto res = stat(entry.name.toStringz, &fileStats);
      column.write(entry, &fileStats);
    }
    writeln();
  }
}

int main(string[] args) {
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
      default:
        throw new Exception("unknown option " ~ c);
      }
    }
  }

  SortOrder sort;

  auto helpInformation = getopt(args,
                                std.getopt.config.bundling,
                                "columns|c", "Specify columns (d,f,s,m,n)", &columnsHandler,
                                "sort|s", "Sort mode (byName, dirsFirst)", &sort,
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

  path = absolutePath(path);
  path = asNormalizedPath(path).array;
  if (!exists(path)) {
    stderr.writeln("Path does not exists: ", path);
    return 1;
  }
  writeln(path);
  auto dir = openDir(path);

  auto sortFunction = &sortByName;
  if (sort == SortOrder.dirsFirst) {
    sortFunction = &sortByNameDirsFirst;
  }
  auto contents = dir.contents.array.sort!(sortFunction);
  writeln("after sort: ", contents);
  Formatter formatter = Formatter(columns);

  foreach (file; contents) {
    formatter.write(file);
  }
  return 0;

}
