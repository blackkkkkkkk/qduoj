<template>
  <Panel shadow :padding="10" class="recent-rank">
    <div slot="title">
      {{$t('m.Recent_Ranklist')}}
      <span class="recent-rank-hint">{{$t('m.Recent_Ranklist_Hint', {days: days})}}</span>
    </div>
    <div slot="extra">
      <Button type="text" @click="goRank">{{$t('m.View_More')}}</Button>
    </div>
    <div class="recent-rank-empty" v-if="loaded && !list.length">
      <p>{{$t('m.No_Recent_Rank')}}</p>
    </div>
    <ul class="recent-rank-list" v-else-if="list.length">
      <li v-for="(item, index) in list" :key="item.user.username">
        <span class="recent-rank-index">{{index + 1}}</span>
        <a class="recent-rank-user" @click="goUser(item.user.username)">{{item.user.username}}</a>
        <span class="recent-rank-accepted">{{item.accepted_number}} {{$t('m.AC')}}</span>
        <span class="recent-rank-total">{{item.submission_number}} {{$t('m.Total')}}</span>
      </li>
    </ul>
  </Panel>
</template>

<script>
  import api from '@oj/api'

  export default {
    name: 'RecentRank',
    props: {
      days: {
        type: Number,
        default: 7
      },
      limit: {
        type: Number,
        default: 10
      }
    },
    data () {
      return {
        list: [],
        loaded: false
      }
    },
    mounted () {
      this.getRecentRank()
    },
    methods: {
      getRecentRank () {
        api.getRecentUserRank(this.days, this.limit).then(res => {
          this.list = res.data.data.results
          this.loaded = true
        }, () => {
          this.list = []
          this.loaded = true
        })
      },
      goUser (username) {
        this.$router.push({
          name: 'user-home',
          query: {username: username}
        })
      },
      goRank () {
        this.$router.push({name: 'acm-rank'})
      }
    }
  }
</script>

<style scoped lang="less">
  .recent-rank-hint {
    margin-left: 10px;
    font-size: 13px;
    font-weight: 400;
    color: #80848f;
  }

  .recent-rank-empty {
    text-align: center;
    font-size: 16px;
    padding: 10px 0;
  }

  .recent-rank-list {
    margin-top: -10px;
    margin-bottom: 10px;
    li {
      display: flex;
      align-items: center;
      list-style: none;
      padding: 12px 20px;
      font-size: 16px;
      border-bottom: 1px solid rgba(187, 187, 187, 0.5);
      &:last-child {
        border-bottom: none;
      }
    }
  }

  .recent-rank-index {
    flex: none;
    width: 40px;
    text-align: center;
    color: #80848f;
  }

  .recent-rank-user {
    flex: 1 1;
    color: #495060;
    &:hover {
      color: #2d8cf0;
      border-bottom: 1px solid #2d8cf0;
    }
  }

  .recent-rank-accepted {
    flex: none;
    width: 120px;
    text-align: center;
  }

  .recent-rank-total {
    flex: none;
    width: 120px;
    text-align: center;
    color: #80848f;
  }
</style>
