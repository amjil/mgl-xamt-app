defmodule Xamt.Repo.Migrations.AddIndexesForUnreadChannels do
  use Ecto.Migration

  def change do
    # 针对 N+1 查询条件 (m.channel_id == ^server_id AND m.inserted_at ...)
    # 建立复合索引，使得数据库只需扫描索引即可判断最新消息
    drop_if_exists index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:channel_id, :inserted_at, :id])

    # channel_reads 上的 unique_index([:user_id, :channel_id]) 已在建表迁移中创建
  end
end
